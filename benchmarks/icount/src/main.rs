// Instrument a wasm module to count the instructions it executes.
//
// Every straight-line run of instructions gets one counter bump at its start,
// so the count is exact and the cost is one add per basic block. Structural
// instructions (block, loop, end, else, nop) are free, like wasmtime's fuel.
// memory.copy and memory.fill count as one instruction each, and the bytes
// they move go to a second counter, since one instruction can move 1 byte or
// 100 KB.
//
//   icount <in.wasm> <out.wasm>
//
// The output exports two mutable i64 globals, `__icount` and `__bulk_bytes`.
use wasm_encoder::reencode::{self, Reencode};
use wasm_encoder::{
    CodeSection, ConstExpr, ExportKind, ExportSection, GlobalSection, GlobalType, Instruction,
    Module, SectionId, ValType,
};
use wasmparser::{Operator, Parser, Payload};

type Err = reencode::Error<std::convert::Infallible>;

struct Counter {
    /// Param count of each defined function, in code section order.
    params: Vec<u32>,
    next_func: usize,
    icount: u32,
    bulk: u32,
    has_global_section: bool,
    globals_emitted: bool,
}

impl Reencode for Counter {
    type Error = std::convert::Infallible;

    fn parse_global_section(
        &mut self,
        globals: &mut GlobalSection,
        section: wasmparser::GlobalSectionReader<'_>,
    ) -> Result<(), Err> {
        reencode::utils::parse_global_section(self, globals, section)?;
        add_counters(globals);
        self.globals_emitted = true;
        Ok(())
    }

    fn intersperse_section_hook(
        &mut self,
        module: &mut Module,
        _after: Option<SectionId>,
        before: Option<SectionId>,
    ) -> Result<(), Err> {
        // A module without globals still needs ours, placed where the global
        // section would sit.
        let past_globals = match before {
            None => true,
            Some(id) => matches!(
                id,
                SectionId::Export
                    | SectionId::Start
                    | SectionId::Element
                    | SectionId::DataCount
                    | SectionId::Code
                    | SectionId::Data
            ),
        };
        if !self.has_global_section && !self.globals_emitted && past_globals {
            let mut globals = GlobalSection::new();
            add_counters(&mut globals);
            module.section(&globals);
            self.globals_emitted = true;
        }
        Ok(())
    }

    fn parse_export_section(
        &mut self,
        exports: &mut ExportSection,
        section: wasmparser::ExportSectionReader<'_>,
    ) -> Result<(), Err> {
        reencode::utils::parse_export_section(self, exports, section)?;
        exports.export("__icount", ExportKind::Global, self.icount);
        exports.export("__bulk_bytes", ExportKind::Global, self.bulk);
        Ok(())
    }

    fn parse_function_body(
        &mut self,
        code: &mut CodeSection,
        func: wasmparser::FunctionBody<'_>,
    ) -> Result<(), Err> {
        let mut locals = Vec::new();
        let mut declared = 0u32;
        for pair in func.get_locals_reader()? {
            let (n, ty) = pair?;
            declared += n;
            locals.push((n, self.val_type(ty)?));
        }
        // A scratch local to read a bulk op's length without disturbing the stack.
        let scratch = self.params[self.next_func] + declared;
        self.next_func += 1;
        locals.push((1, ValType::I32));
        let mut f = wasm_encoder::Function::new(locals);

        let mut segment: Vec<Instruction> = Vec::new();
        let mut cost: i64 = 0;
        let mut reader = func.get_operators_reader()?;
        while !reader.eof() {
            let op = reader.read()?;
            let (free, ends_block, bulk) = classify(&op);
            let ins = self.instruction(op)?;
            if bulk {
                // Stack is [dst, src|val, len]: tee len aside and add it.
                segment.push(Instruction::LocalTee(scratch));
                segment.push(Instruction::GlobalGet(self.bulk));
                segment.push(Instruction::LocalGet(scratch));
                segment.push(Instruction::I64ExtendI32U);
                segment.push(Instruction::I64Add);
                segment.push(Instruction::GlobalSet(self.bulk));
            }
            segment.push(ins);
            if !free {
                cost += 1;
            }
            if ends_block {
                flush(&mut f, &mut segment, &mut cost, self.icount);
            }
        }
        flush(&mut f, &mut segment, &mut cost, self.icount);
        code.function(&f);
        Ok(())
    }
}

fn add_counters(globals: &mut GlobalSection) {
    for _ in 0..2 {
        globals.global(
            GlobalType { val_type: ValType::I64, mutable: true, shared: false },
            &ConstExpr::i64_const(0),
        );
    }
}

/// Emit the segment's counter bump, then the segment itself.
fn flush(f: &mut wasm_encoder::Function, segment: &mut Vec<Instruction>, cost: &mut i64, g: u32) {
    if *cost > 0 {
        f.instruction(&Instruction::GlobalGet(g));
        f.instruction(&Instruction::I64Const(*cost));
        f.instruction(&Instruction::I64Add);
        f.instruction(&Instruction::GlobalSet(g));
    }
    for ins in segment.drain(..) {
        f.instruction(&ins);
    }
    *cost = 0;
}

/// (free, ends a straight-line run, moves a dynamic number of bytes)
fn classify(op: &Operator) -> (bool, bool, bool) {
    use Operator::*;
    match op {
        Nop => (true, false, false),
        Block { .. } | Loop { .. } | Else | End => (true, true, false),
        If { .. } | Br { .. } | BrIf { .. } | BrTable { .. } | Return | Unreachable => (false, true, false),
        BrOnNull { .. } | BrOnNonNull { .. } | BrOnCast { .. } | BrOnCastFail { .. } => (false, true, false),
        Try { .. } | TryTable { .. } | Catch { .. } | CatchAll | Delegate { .. } | Throw { .. } | ThrowRef | Rethrow { .. } => {
            (false, true, false)
        }
        ReturnCall { .. } | ReturnCallIndirect { .. } | ReturnCallRef { .. } => (false, true, false),
        MemoryCopy { .. } | MemoryFill { .. } => (false, false, true),
        _ => (false, false, false),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: icount <in.wasm> <out.wasm>");
        std::process::exit(2);
    }
    let input = std::fs::read(&args[1]).expect("read input");

    // First pass: function signatures, so each body knows its param count,
    // and the global count, so the counters' indices are known up front.
    let mut types: Vec<u32> = Vec::new();
    let mut params = Vec::new();
    let mut imported_globals = 0u32;
    let mut defined_globals = 0u32;
    let mut has_global_section = false;
    for payload in Parser::new(0).parse_all(&input) {
        match payload.expect("parse") {
            Payload::TypeSection(r) => {
                for rec in r.into_iter() {
                    for sub in rec.expect("type").into_types() {
                        let n = match &sub.composite_type.inner {
                            wasmparser::CompositeInnerType::Func(ft) => ft.params().len() as u32,
                            _ => 0,
                        };
                        types.push(n);
                    }
                }
            }
            Payload::ImportSection(r) => {
                for imp in r.into_imports() {
                    if let wasmparser::TypeRef::Global(_) = imp.expect("import").ty {
                        imported_globals += 1;
                    }
                }
            }
            Payload::FunctionSection(r) => {
                for t in r {
                    params.push(types[t.expect("func") as usize]);
                }
            }
            Payload::GlobalSection(r) => {
                has_global_section = true;
                defined_globals = r.count();
            }
            _ => {}
        }
    }

    let icount = imported_globals + defined_globals;
    let mut counter = Counter {
        params,
        next_func: 0,
        icount,
        bulk: icount + 1,
        has_global_section,
        globals_emitted: false,
    };
    let mut module = Module::new();
    counter
        .parse_core_module(&mut module, Parser::new(0), &input)
        .expect("instrument");
    let out = module.finish();
    wasmparser::Validator::new_with_features(wasmparser::WasmFeatures::all())
        .validate_all(&out)
        .expect("instrumented module validates");
    std::fs::write(&args[2], out).expect("write output");
}
