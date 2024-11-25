platform ""
    requires { Model } {
        init : {} -> Model,
    }
    exposes [Stdout]
    packages {}
    imports []
    provides [initForHost]

#import Effect

initForHost : {} -> Model
initForHost = \{} -> init {}
