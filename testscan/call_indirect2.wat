(module
  (func $add (result i64)
    i64.const 13
  )
  (table 0 anyfunc)
  (func $test (result i64)
    i32.const 0     ;; calling $add
    call_indirect (result i64) ;; type 0 (the only type used in this function)
  )
)
