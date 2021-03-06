import _CJavaScriptKit

public class JSFunction: JSObject {
    @discardableResult
    public func callAsFunction(this: JSObject? = nil, arguments: [JSValueConvertible]) -> JSValue {
        let result = arguments.withRawJSValues { rawValues in
            rawValues.withUnsafeBufferPointer { bufferPointer -> RawJSValue in
                let argv = bufferPointer.baseAddress
                let argc = bufferPointer.count
                var result = RawJSValue()
                if let thisId = this?.id {
                    _call_function_with_this(thisId,
                                             self.id, argv, Int32(argc),
                                             &result.kind, &result.payload1, &result.payload2, &result.payload3)
                } else {
                    _call_function(
                        self.id, argv, Int32(argc),
                        &result.kind, &result.payload1, &result.payload2, &result.payload3
                    )
                }
                return result
            }
        }
        return result.jsValue()
    }

    @discardableResult
    public func callAsFunction(this: JSObject? = nil, _ arguments: JSValueConvertible...) -> JSValue {
        self(this: this, arguments: arguments)
    }

    public func new(_ arguments: JSValueConvertible...) -> JSObject {
        new(arguments: arguments)
    }

    // Guaranteed to return an object because either:
    // a) the constructor explicitly returns an object, or
    // b) the constructor returns nothing, which causes JS to return the `this` value, or
    // c) the constructor returns undefined, null or a non-object, in which case JS also returns `this`.
    public func new(arguments: [JSValueConvertible]) -> JSObject {
        arguments.withRawJSValues { rawValues in
            rawValues.withUnsafeBufferPointer { bufferPointer in
                let argv = bufferPointer.baseAddress
                let argc = bufferPointer.count
                var resultObj = JavaScriptObjectRef()
                _call_new(
                    self.id, argv, Int32(argc),
                    &resultObj
                )
                return JSObject(id: resultObj)
            }
        }
    }

    @available(*, unavailable, message: "Please use JSClosure instead")
    public static func from(_: @escaping ([JSValue]) -> JSValue) -> JSFunction {
        fatalError("unavailable")
    }

    override public func jsValue() -> JSValue {
        .function(self)
    }
}

public class JSClosure: JSFunction {
    static var sharedFunctions: [JavaScriptHostFuncRef: ([JSValue]) -> JSValue] = [:]

    private var hostFuncRef: JavaScriptHostFuncRef = 0

    private var isReleased = false

    public init(_ body: @escaping ([JSValue]) -> JSValue) {
        super.init(id: 0)
        let objectId = ObjectIdentifier(self)
        let funcRef = JavaScriptHostFuncRef(bitPattern: Int32(objectId.hashValue))
        Self.sharedFunctions[funcRef] = body

        var objectRef: JavaScriptObjectRef = 0
        _create_function(funcRef, &objectRef)

        hostFuncRef = funcRef
        id = objectRef
    }

    convenience public init(_ body: @escaping ([JSValue]) -> ()) {
        self.init { (arguments: [JSValue]) -> JSValue in
            body(arguments)
            return .undefined
        }
    }

    public func release() {
        Self.sharedFunctions[hostFuncRef] = nil
        isReleased = true
    }

    deinit {
        guard isReleased else {
            fatalError("""
            release() must be called on closures manually before deallocating.
            This is caused by the lack of support for the `FinalizationRegistry` API in Safari.
            """)
        }
    }
}

@_cdecl("swjs_prepare_host_function_call")
func _prepare_host_function_call(_ argc: Int32) -> UnsafeMutableRawPointer {
    let argumentSize = MemoryLayout<RawJSValue>.size * Int(argc)
    return malloc(Int(argumentSize))!
}

@_cdecl("swjs_cleanup_host_function_call")
func _cleanup_host_function_call(_ pointer: UnsafeMutableRawPointer) {
    free(pointer)
}

@_cdecl("swjs_call_host_function")
func _call_host_function(
    _ hostFuncRef: JavaScriptHostFuncRef,
    _ argv: UnsafePointer<RawJSValue>, _ argc: Int32,
    _ callbackFuncRef: JavaScriptObjectRef
) {
    guard let hostFunc = JSClosure.sharedFunctions[hostFuncRef] else {
        fatalError("The function was already released")
    }
    let arguments = UnsafeBufferPointer(start: argv, count: Int(argc)).map {
        $0.jsValue()
    }
    let result = hostFunc(arguments)
    let callbackFuncRef = JSFunction(id: callbackFuncRef)
    _ = callbackFuncRef(result)
}
