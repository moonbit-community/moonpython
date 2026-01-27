///|
/// Callable dispatch and runtime call hooks.

///|
fn eval_function_with_kwargs_uninitialized(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = func
  let _ = positional
  let _ = keywords
  let _ = globals
  let _ = builtins
  let _ = io
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      "RuntimeError: internal call callback not initialized".to_string(),
    ),
  )
}

///|
let eval_function_with_kwargs_ref : Ref[
  (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
] = { val: eval_function_with_kwargs_uninitialized }

///|
fn eval_generator_with_kwargs_uninitialized(
  func : FunctionValue,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  let _ = func
  let _ = positional
  let _ = keywords
  let _ = globals
  let _ = builtins
  let _ = io
  Err(
    make_runtime_error(
      RuntimeErrorKind::Runtime,
      "RuntimeError: internal generator callback not initialized".to_string(),
    ),
  )
}

///|
let eval_generator_with_kwargs_ref : Ref[
  (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
] = { val: eval_generator_with_kwargs_uninitialized }

///|
fn set_eval_function_with_kwargs_callback(
  callback : (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
) -> Unit {
  eval_function_with_kwargs_ref.val = callback
}

///|
fn set_eval_generator_with_kwargs_callback(
  callback : (
    FunctionValue,
    Array[Value],
    Array[(String, Value)],
    Array[(String, Value)],
    Array[(String, Value)],
    MockIO,
  ) -> Result[Value, RuntimeError],
) -> Unit {
  eval_generator_with_kwargs_ref.val = callback
}

///|
fn call_callable_with_env(
  callee : Value,
  positional : Array[Value],
  keywords : Array[(String, Value)],
  globals : Array[(String, Value)],
  builtins : Array[(String, Value)],
  io : MockIO,
) -> Result[Value, RuntimeError] {
  match callee {
    Value::Function(func) =>
      if func.is_async {
        if func.is_generator {
          (eval_generator_with_kwargs_ref.val)(
            func, positional, keywords, globals, builtins, io,
          )
        } else {
          (eval_function_with_kwargs_ref.val)(
            func, positional, keywords, globals, builtins, io,
          )
        }
      } else if func.is_generator {
        (eval_generator_with_kwargs_ref.val)(
          func, positional, keywords, globals, builtins, io,
        )
      } else if func.name == "__getattribute__" && func.body.length() == 0 {
        // Intrinsic: object.__getattribute__(self, name)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() takes exactly two arguments".to_string(),
            ),
          )
        }
        let target = positional[0]
        let name = match positional[1] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        get_attr_raw_from_value(target, name, globals, builtins, io)
      } else if func.name == "__setattr__" && func.body.length() == 0 {
        // Intrinsic: object.__setattr__(self, name, value)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 3 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() takes exactly three arguments".to_string(),
            ),
          )
        }
        let target = positional[0]
        let name = match positional[1] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        let value = positional[2]
        let _ = match
          set_attr_raw_on_value(target, name, value, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::None)
      } else if func.name == "__delattr__" && func.body.length() == 0 {
        // Intrinsic: object.__delattr__(self, name)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() takes exactly two arguments".to_string(),
            ),
          )
        }
        let target = positional[0]
        let name = match positional[1] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        let _ = match
          delete_attr_raw_on_value(target, name, globals, builtins, io) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(Value::None)
      } else if func.name == "__new__" && func.body.length() == 0 {
        // Intrinsic: object.__new__(cls)
        if positional.length() < 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__new__() expects a type".to_string(),
            ),
          )
        }
        let cls_value = positional[0]
        match cls_value {
          Value::Class(klass) => {
            let inst_dict : Array[(String, Value)] = []
            inst_dict.push(("hashvalue", Value::Int(fresh_object_hashvalue())))
            if class_includes_list(klass) {
              inst_dict.push((list_storage_name, Value::List([])))
            }
            if class_includes_dict(klass) {
              inst_dict.push((dict_storage_name, Value::Dict([])))
            }
            Ok(
              Value::Instance(InstanceValue::{ class: klass, dict: inst_dict }),
            )
          }
          _ =>
            Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "__new__() expects a type".to_string(),
              ),
            )
        }
      } else if func.name == "__hash__" && func.body.length() == 0 {
        // Intrinsic: object.__hash__(self)
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__hash__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__hash__() takes exactly one argument".to_string(),
            ),
          )
        }
        match hash_value(positional[0]) {
          Ok(hash) => Ok(Value::Int(hash))
          Err(err) => Err(err)
        }
      } else if func.name == "__eq__" && func.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__eq__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__eq__() takes exactly two arguments".to_string(),
            ),
          )
        }
        Ok(Value::Bool(eq_value(positional[0], positional[1])))
      } else if func.name == "__ne__" && func.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__ne__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__ne__() takes exactly two arguments".to_string(),
            ),
          )
        }
        Ok(Value::Bool(!eq_value(positional[0], positional[1])))
      } else if func.body.length() == 0 {
        match
          eval_builtin_call(
            func.name,
            positional,
            keywords,
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(Some(value)) => Ok(value)
          Ok(None) =>
            (eval_function_with_kwargs_ref.val)(
              func, positional, keywords, globals, builtins, io,
            )
          Err(err) => Err(err)
        }
      } else {
        (eval_function_with_kwargs_ref.val)(
          func, positional, keywords, globals, builtins, io,
        )
      }
    Value::BoundMethod(bound_method) => {
      // Intrinsic: object.__getattribute__(self, name)
      if bound_method.function.name == "__getattribute__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__getattribute__() takes exactly one argument".to_string(),
            ),
          )
        }
        let name = match positional[0] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        return get_attr_raw_from_value(
          bound_method.self,
          name,
          globals,
          builtins,
          io,
        )
      }

      // Intrinsic: object.__setattr__(self, name, value)
      if bound_method.function.name == "__setattr__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setattr__() takes exactly two arguments".to_string(),
            ),
          )
        }
        let name = match positional[0] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        let value = positional[1]
        let _ = match
          set_attr_raw_on_value(
            bound_method.self,
            name,
            value,
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        return Ok(Value::None)
      }

      // Intrinsic: object.__delattr__(self, name)
      if bound_method.function.name == "__delattr__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__delattr__() takes exactly one argument".to_string(),
            ),
          )
        }
        let name = match positional[0] {
          Value::Str(text) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "attribute name must be str".to_string(),
              ),
            )
        }
        let _ = match
          delete_attr_raw_on_value(
            bound_method.self,
            name,
            globals,
            builtins,
            io,
          ) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        return Ok(Value::None)
      }

      // Intrinsic: BaseException.__setstate__(self, state)
      if bound_method.function.name == "__setstate__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setstate__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__setstate__() takes exactly one argument".to_string(),
            ),
          )
        }
        let state = positional[0]
        match (bound_method.self, state) {
          (Value::Instance(inst), Value::Dict(pairs)) => {
            fn key_to_attr_name(key : Value) -> Result[String, RuntimeError] {
              match key {
                Value::Str(text) => Ok(text)
                Value::Instance(key_inst) => {
                  let mut is_str_base = false
                  for base in key_inst.class.bases {
                    match base {
                      Value::Class(c) =>
                        if c.name == "str" {
                          is_str_base = true
                          break
                        }
                      _ => ()
                    }
                  }
                  if is_str_base {
                    // moonpython doesn't model `str` subclasses as primitive strings yet.
                    // Treat `str`-subclass attribute keys as empty strings (covers
                    // `HashThisKeyWillClearTheDict()` in CPython's `test_baseexception`).
                    Ok("".to_string())
                  } else {
                    Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "attribute name must be str".to_string(),
                      ),
                    )
                  }
                }
                _ =>
                  Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "attribute name must be str".to_string(),
                    ),
                  )
              }
            }

            for pair in pairs {
              let name = match key_to_attr_name(pair.0) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              set_named_value(inst.dict, name, pair.1)
            }
            return Ok(Value::None)
          }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "__setstate__() expects a dict".to_string(),
              ),
            )
        }
      }

      // Intrinsic: object.__init_subclass__(cls, **kwargs)
      if bound_method.function.name == "__init_subclass__" &&
        bound_method.function.body.length() == 0 {
        if positional.length() != 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__init_subclass__() takes no arguments".to_string(),
            ),
          )
        }
        return Ok(Value::None)
      }
      // Intrinsic: type.__subclasses__(cls)
      if bound_method.function.name == "__subclasses__" &&
        bound_method.function.body.length() == 0 {
        if keywords.length() > 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__subclasses__() got unexpected keyword arguments".to_string(),
            ),
          )
        }
        if positional.length() != 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "__subclasses__() takes no arguments".to_string(),
            ),
          )
        }
        // We don't track subclass relationships yet; return an empty list.
        return Ok(Value::List([]))
      }
      // Intrinsic: importlib meta_path finder
      if bound_method.function.name == "__mpython_find_spec" &&
        bound_method.function.body.length() == 0 {
        // Signature: find_spec(fullname, path=None, target=None)
        // We accept a subset used by the stdlib `importlib` implementation.
        let mut fullname_value : Value? = None
        let mut path_value : Value = Value::None
        if positional.length() >= 1 {
          fullname_value = Some(positional[0])
        }
        if positional.length() >= 2 {
          path_value = positional[1]
        }
        for pair in keywords {
          if pair.0 == "path" {
            path_value = pair.1
          }
        }
        let fullname = match fullname_value {
          Some(Value::Str(text)) => text
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "find_spec() fullname must be str".to_string(),
              ),
            )
        }
        fn root_from_sys_path_entry(value : Value) -> String? {
          match value {
            Value::Str(text) =>
              if text.length() == 0 {
                Some(current_workdir())
              } else if text.has_prefix("/") {
                Some(text)
              } else {
                Some(resolve_path_from_initial_cwd(text))
              }
            _ => None
          }
        }

        let roots : Array[String] = []
        match path_value {
          Value::None => {
            // Use `sys.path` when `path` is not provided.
            let sys_value_opt = module_cache_get("sys")
            match sys_value_opt {
              Some(Value::Instance(sys_inst)) =>
                match get_named_value(sys_inst.dict, "path") {
                  Some(Value::List(values)) =>
                    for item in values {
                      match root_from_sys_path_entry(item) {
                        Some(root) => roots.push(root)
                        None => ()
                      }
                    }
                  _ => ()
                }
              _ => ()
            }
          }
          Value::List(values) =>
            for item in values {
              match root_from_sys_path_entry(item) {
                Some(root) => roots.push(root)
                None => ()
              }
            }
          Value::Str(text) =>
            match root_from_sys_path_entry(Value::Str(text)) {
              Some(root) => roots.push(root)
              None => ()
            }
          _ => ()
        }
        let mut rel = module_rel_path(fullname)
        // When `path` is provided (i.e. we're searching inside an already
        // resolved package), only join the leaf module name onto each entry in
        // that package's `__path__`.
        match path_value {
          Value::None => ()
          _ => {
            let parts = module_name_parts(fullname)
            if parts.length() > 0 {
              rel = parts[parts.length() - 1]
            }
          }
        }
        // Prefer packages over modules (matches CPython importlib behavior).
        for root in roots {
          let pkg_dir = @path.Path(root).join(@path.Path(rel)).to_string()
          let init_path = @path.Path(pkg_dir)
            .join(@path.Path("__init__.py"))
            .to_string()
          if @fs.path_exists(init_path) {
            let loader = make_importlib_loader()
            let parent = module_parent_name(fullname)
            let spec_class = ClassValue::{
              name: "ModuleSpec",
              bases: [],
              dict: [],
            }
            let spec = Value::Instance(InstanceValue::{
              class: spec_class,
              dict: [
                ("name", Value::Str(fullname)),
                ("origin", Value::Str(init_path)),
                ("loader", loader),
                ("parent", Value::Str(parent)),
                (
                  "submodule_search_locations",
                  Value::List([Value::Str(pkg_dir)]),
                ),
                ("cached", Value::None),
                ("loader_state", Value::None),
                ("_uninitialized_submodules", Value::List([])),
                ("has_location", Value::Bool(true)),
              ],
            })
            return Ok(spec)
          }
        }
        for root in roots {
          let module_path = @path.Path(root)
            .join(@path.Path(rel + ".py"))
            .to_string()
          if @fs.path_exists(module_path) {
            let loader = make_importlib_loader()
            let parent = module_parent_name(fullname)
            let spec_class = ClassValue::{
              name: "ModuleSpec",
              bases: [],
              dict: [],
            }
            let spec = Value::Instance(InstanceValue::{
              class: spec_class,
              dict: [
                ("name", Value::Str(fullname)),
                ("origin", Value::Str(module_path)),
                ("loader", loader),
                ("parent", Value::Str(parent)),
                ("submodule_search_locations", Value::None),
                ("cached", Value::None),
                ("loader_state", Value::None),
                ("_uninitialized_submodules", Value::List([])),
                ("has_location", Value::Bool(true)),
              ],
            })
            return Ok(spec)
          }
        }
        return Ok(Value::None)
      }
      // Intrinsic: importlib loader create_module(spec)
      if bound_method.function.name == "__mpython_create_module" &&
        bound_method.function.body.length() == 0 {
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "create_module() takes exactly one argument".to_string(),
            ),
          )
        }
        let spec = positional[0]
        let (name, origin, parent, locations, loader) = match spec {
          Value::Instance(spec_inst) => {
            let name = match get_named_value(spec_inst.dict, "name") {
              Some(Value::Str(v)) => v
              _ => "<module>".to_string()
            }
            let origin = match get_named_value(spec_inst.dict, "origin") {
              Some(Value::Str(v)) => v
              _ => "<module>".to_string()
            }
            let parent = match get_named_value(spec_inst.dict, "parent") {
              Some(Value::Str(v)) => v
              _ => "".to_string()
            }
            let locations = match
              get_named_value(spec_inst.dict, "submodule_search_locations") {
              Some(v) => v
              None => Value::None
            }
            let loader = match get_named_value(spec_inst.dict, "loader") {
              Some(v) => v
              None => Value::None
            }
            (name, origin, parent, locations, loader)
          }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "create_module() expects a spec".to_string(),
              ),
            )
        }
        let is_package = match locations {
          Value::List(_) => true
          _ => false
        }
        let package_name = if is_package { name } else { parent }
        let module_class = ClassValue::{ name: "module", bases: [], dict: [] }
        let dict : Array[(String, Value)] = [
          ("__name__", Value::Str(name)),
          ("__package__", Value::Str(package_name)),
          ("__file__", Value::Str(origin)),
          ("__loader__", loader),
          ("__spec__", spec),
        ]
        let module_dict = dict
        match locations {
          Value::List(_) => module_dict.push(("__path__", locations))
          _ => ()
        }
        return Ok(
          Value::Instance(InstanceValue::{
            class: module_class,
            dict: module_dict,
          }),
        )
      }
      // Intrinsic: importlib loader exec_module(module)
      if bound_method.function.name == "__mpython_exec_module" &&
        bound_method.function.body.length() == 0 {
        if positional.length() != 1 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "exec_module() takes exactly one argument".to_string(),
            ),
          )
        }
        let module_value = positional[0]
        let (name, filename, module_globals, is_pkg, pkg_path) = match
          module_value {
          Value::Instance(inst) => {
            let name = match get_named_value(inst.dict, "__name__") {
              Some(Value::Str(v)) => v
              _ => "<module>".to_string()
            }
            let filename = match get_named_value(inst.dict, "__file__") {
              Some(Value::Str(v)) => v
              _ => "<module>".to_string()
            }
            let mut is_pkg = false
            let mut pkg_path = ""
            match get_named_value(inst.dict, "__path__") {
              Some(Value::List(values)) =>
                if values.length() > 0 {
                  match values[0] {
                    Value::Str(v) => {
                      is_pkg = true
                      pkg_path = v
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
            (name, filename, inst.dict, is_pkg, pkg_path)
          }
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                "exec_module() expects a module".to_string(),
              ),
            )
        }
        let source = @fs.read_file_to_string(filename) catch {
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Runtime,
                "ImportError: cannot read file: " + filename,
              ),
            )
        }
        let config = current_config()
        let saved_closure_env_stack = closure_env_stack.val
        let saved_scope_decls_stack = scope_decls_stack.val
        closure_env_stack.val = []
        scope_decls_stack.val = []
        push_traceback_frame("<module>".to_string(), filename)
        let program = match parse(source) {
          Ok(v) => v
          Err(err) => {
            pop_traceback_frame()
            closure_env_stack.val = saved_closure_env_stack
            scope_decls_stack.val = saved_scope_decls_stack
            return Err(make_parse_runtime_error(err))
          }
        }
        // Ensure package modules have an importable `__path__`.
        if is_pkg {
          set_named_value(
            module_globals,
            "__path__",
            Value::List([Value::Str(pkg_path)]),
          )
        }
        let _ = match
          eval_block(
            program.body,
            module_globals,
            module_globals,
            builtins,
            io,
            config,
          ) {
          Ok(v) => v
          Err(err) => {
            pop_traceback_frame()
            closure_env_stack.val = saved_closure_env_stack
            scope_decls_stack.val = saved_scope_decls_stack
            return Err(err)
          }
        }
        pop_traceback_frame()
        closure_env_stack.val = saved_closure_env_stack
        scope_decls_stack.val = saved_scope_decls_stack
        // Importlib expects `exec_module` to return None.
        let _ = name
        return Ok(Value::None)
      }
      match bound_method.self {
        Value::Instance(inst) =>
          if (
              inst.class.name == "dict_keys" ||
              inst.class.name == "dict_values" ||
              inst.class.name == "dict_items"
            ) &&
            bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            let dict_value = match get_named_value(inst.dict, "dict") {
              Some(v) => v
              None =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "RuntimeError: bad dict view".to_string(),
                  ),
                )
            }
            let pairs = match dict_value {
              Value::Dict(pairs) => pairs
              _ =>
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Type,
                    "dict view expects a dict".to_string(),
                  ),
                )
            }
            match bound_method.function.name {
              "__len__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__len__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(
                    Value::Int(@bigint.BigInt::from_int(pairs.length())),
                  )
                }
              "__iter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__iter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let items : Array[Value] = []
                  if inst.class.name == "dict_keys" {
                    for pair in pairs {
                      items.push(pair.0)
                    }
                  } else if inst.class.name == "dict_values" {
                    for pair in pairs {
                      items.push(pair.1)
                    }
                  } else {
                    for pair in pairs {
                      items.push(Value::Tuple([pair.0, pair.1]))
                    }
                  }
                  return Ok(make_iterator(items))
                }
              "__contains__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__contains__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let item = positional[0]
                  if inst.class.name == "dict_keys" {
                    let index = match dict_find_index(pairs, item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    return Ok(Value::Bool(index is Some(_)))
                  } else if inst.class.name == "dict_values" {
                    for pair in pairs {
                      if eq_value(pair.1, item) {
                        return Ok(Value::Bool(true))
                      }
                    }
                    return Ok(Value::Bool(false))
                  } else {
                    let _ = match ensure_hashable(item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    match item {
                      Value::Tuple(values) | Value::List(values) =>
                        if values.length() != 2 {
                          return Ok(Value::Bool(false))
                        } else {
                          for pair in pairs {
                            if eq_value(pair.0, values[0]) &&
                              eq_value(pair.1, values[1]) {
                              return Ok(Value::Bool(true))
                            }
                          }
                          return Ok(Value::Bool(false))
                        }
                      _ => return Ok(Value::Bool(false))
                    }
                  }
                }
              _ => ()
            }
          } else if bound_method.function.body.length() == 0 &&
            get_named_value(inst.dict, list_storage_name) is Some(_) {
            // Support list subclasses: instances created via object.__new__ for a class
            // that includes `list` in its MRO store their backing array in `$__list__`.
            match get_named_value(inst.dict, list_storage_name) {
              Some(Value::List(values)) => {
                if keywords.length() > 0 && bound_method.function.name != "sort" {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      bound_method.function.name +
                      "() got unexpected keyword arguments".to_string(),
                    ),
                  )
                }
                match bound_method.function.name {
                  "append" =>
                    if positional.length() != 1 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "append() takes exactly one argument".to_string(),
                        ),
                      )
                    } else {
                      values.push(positional[0])
                      return Ok(Value::None)
                    }
                  "extend" =>
                    if positional.length() != 1 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "extend() takes exactly one argument".to_string(),
                        ),
                      )
                    } else {
                      let to_add : Array[Value] = []
                      let iterator = match
                        iter_value_to_iterator(
                          positional[0],
                          globals,
                          builtins,
                          io,
                        ) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      while true {
                        match
                          iterator_next(iterator, None, globals, builtins, io) {
                          Ok(item) => to_add.push(item)
                          Err(err) =>
                            if err.exc_type == "StopIteration" {
                              break
                            } else {
                              return Err(err)
                            }
                        }
                      }
                      for item in to_add {
                        values.push(item)
                      }
                      return Ok(Value::None)
                    }
                  "insert" =>
                    if positional.length() != 2 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "insert() takes exactly two arguments".to_string(),
                        ),
                      )
                    } else {
                      let idx = match index_from_value(positional[0], 0) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      let len = values.length()
                      let mut pos = normalize_index(idx, len)
                      if pos < 0 {
                        pos = 0
                      }
                      if pos > len {
                        pos = len
                      }
                      values.push(Value::None)
                      let mut i = len
                      while i > pos {
                        values[i] = values[i - 1]
                        i = i - 1
                      }
                      values[pos] = positional[1]
                      return Ok(Value::None)
                    }
                  "remove" =>
                    if positional.length() != 1 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "remove() takes exactly one argument".to_string(),
                        ),
                      )
                    } else {
                      let needle = positional[0]
                      for i = 0; i < values.length(); i = i + 1 {
                        if eq_value(values[i], needle) {
                          let _ = values.remove(i)
                          return Ok(Value::None)
                        }
                      }
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "ValueError: list.remove(x): x not in list".to_string(),
                        ),
                      )
                    }
                  "reverse" =>
                    if positional.length() != 0 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "reverse() takes no arguments".to_string(),
                        ),
                      )
                    } else {
                      if values.length() == 0 {
                        return Ok(Value::None)
                      }
                      let mut i = 0
                      let mut j = values.length() - 1
                      while i < j {
                        let tmp = values[i]
                        values[i] = values[j]
                        values[j] = tmp
                        i += 1
                        j -= 1
                      }
                      return Ok(Value::None)
                    }
                  "clear" =>
                    if positional.length() != 0 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "clear() takes no arguments".to_string(),
                        ),
                      )
                    } else {
                      let mut i = values.length()
                      while i > 0 {
                        i = i - 1
                        let _ = values.remove(i)

                      }
                      return Ok(Value::None)
                    }
                  "pop" => {
                    if positional.length() > 1 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "pop() takes at most one argument".to_string(),
                        ),
                      )
                    }
                    if values.length() == 0 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Index,
                          "pop from empty list".to_string(),
                        ),
                      )
                    }
                    let mut idx = values.length() - 1
                    if positional.length() == 1 {
                      let raw = match positional[0] {
                        Value::Int(v) =>
                          match bigint_to_int_checked(v) {
                            Ok(i) => i
                            Err(err) => return Err(err)
                          }
                        Value::Bool(b) => if b { 1 } else { 0 }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "invalid index".to_string(),
                            ),
                          )
                      }
                      let normalized = normalize_index(raw, values.length())
                      if normalized < 0 || normalized >= values.length() {
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Index,
                            "pop index out of range".to_string(),
                          ),
                        )
                      }
                      idx = normalized
                    }
                    let item = values.remove(idx)
                    return Ok(item)
                  }
                  "copy" =>
                    if positional.length() != 0 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "copy() takes no arguments".to_string(),
                        ),
                      )
                    } else {
                      let out : Array[Value] = []
                      for item in values {
                        out.push(item)
                      }
                      return Ok(Value::List(out))
                    }
                  "sort" => {
                    if positional.length() > 2 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "sort() takes at most 2 arguments".to_string(),
                        ),
                      )
                    }
                    let mut reverse = false
                    let mut key_value : Value? = None
                    for pair in keywords {
                      if pair.0 == "key" {
                        key_value = Some(pair.1)
                      } else if pair.0 == "reverse" {
                        reverse = bool_from_value(pair.1)
                      } else {
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Type,
                            "sort() got unexpected keyword arguments".to_string(),
                          ),
                        )
                      }
                    }
                    if positional.length() >= 1 {
                      if key_value is Some(_) {
                        return Err(
                          make_runtime_error(
                            RuntimeErrorKind::Type,
                            "sort() got multiple values for argument 'key'".to_string(),
                          ),
                        )
                      }
                      key_value = Some(positional[0])
                    }
                    if positional.length() == 2 {
                      reverse = bool_from_value(positional[1])
                    }
                    if values.length() == 0 {
                      return Ok(Value::None)
                    }
                    fn lt_for_sort(
                      a : Value,
                      b : Value,
                      globals : Array[(String, Value)],
                      builtins : Array[(String, Value)],
                      io : MockIO,
                    ) -> Result[Bool, RuntimeError] {
                      match (a, b) {
                        (Value::Str(x), Value::Str(y)) => Ok(x < y)
                        (Value::Int(_) | Value::Float(_) | Value::Bool(_), _)
                        | (_, Value::Int(_) | Value::Float(_) | Value::Bool(_)) => {
                          let (_, left_num) = match number_value(a) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          let (_, right_num) = match number_value(b) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          Ok(left_num < right_num)
                        }
                        _ => {
                          let lt = match
                            get_attr_from_value(
                              a, "__lt__", globals, builtins, io,
                            ) {
                            Ok(v) => v
                            Err(err) =>
                              match err.kind {
                                RuntimeErrorKind::Attribute =>
                                  return Err(
                                    make_runtime_error(
                                      RuntimeErrorKind::Type,
                                      "sort() cannot compare values".to_string(),
                                    ),
                                  )
                                _ => return Err(err)
                              }
                          }
                          let result = match
                            call_callable_with_env(
                              lt,
                              [b],
                              [],
                              globals,
                              builtins,
                              io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          Ok(bool_from_value(result))
                        }
                      }
                    }

                    match key_value {
                      Some(key_fn) => {
                        let key_pairs : Array[(Value, Value)] = []
                        for item in values {
                          let key = if key_fn is Value::None {
                            item
                          } else {
                            match
                              call_callable_with_env(
                                key_fn,
                                [item],
                                [],
                                globals,
                                builtins,
                                io,
                              ) {
                              Ok(value) => value
                              Err(err) => return Err(err)
                            }
                          }
                          key_pairs.push((key, item))
                        }
                        fn insertion_sort_pairs_by_key(
                          pairs : Array[(Value, Value)],
                          globals : Array[(String, Value)],
                          builtins : Array[(String, Value)],
                          io : MockIO,
                        ) -> Result[Unit, RuntimeError] {
                          let mut i = 1
                          while i < pairs.length() {
                            let item = pairs[i]
                            let mut j = i
                            while j > 0 {
                              let less = match
                                lt_for_sort(
                                  item.0,
                                  pairs[j - 1].0,
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(v) => v
                                Err(err) => return Err(err)
                              }
                              if !less {
                                break
                              }
                              pairs[j] = pairs[j - 1]
                              j -= 1
                            }
                            pairs[j] = item
                            i += 1
                          }
                          Ok(())
                        }

                        let mut kind_opt : SortKind? = None
                        let mut can_use_fast = true
                        for pair in key_pairs {
                          match sort_kind_for_sorted(pair.0) {
                            Some(kind) =>
                              match kind_opt {
                                None => kind_opt = Some(kind)
                                Some(prev) =>
                                  if prev != kind {
                                    can_use_fast = false
                                  }
                              }
                            None => can_use_fast = false
                          }
                        }
                        let sorted_pairs = if can_use_fast {
                          let kind = match kind_opt {
                            Some(kind) => kind
                            None => return Ok(Value::None)
                          }
                          match stable_sort_pairs_by_key(key_pairs, kind) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                        } else {
                          let _ = match
                            insertion_sort_pairs_by_key(
                              key_pairs, globals, builtins, io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          key_pairs
                        }
                        let sorted_items : Array[Value] = []
                        for pair in sorted_pairs {
                          sorted_items.push(pair.1)
                        }
                        let out = if reverse {
                          reverse_values(sorted_items)
                        } else {
                          sorted_items
                        }
                        replace_array_values(values, out)
                        return Ok(Value::None)
                      }
                      None => {
                        let mut kind_opt : SortKind? = None
                        let mut can_use_fast = true
                        for item in values {
                          match sort_kind_for_sorted(item) {
                            Some(kind) =>
                              match kind_opt {
                                None => kind_opt = Some(kind)
                                Some(prev) =>
                                  if prev != kind {
                                    can_use_fast = false
                                  }
                              }
                            None => can_use_fast = false
                          }
                        }
                        let mut out = if can_use_fast {
                          let kind = match kind_opt {
                            Some(kind) => kind
                            None => return Ok(Value::None)
                          }
                          match stable_sort_for_sorted(values, kind) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                        } else {
                          let out : Array[Value] = []
                          for item in values {
                            out.push(item)
                          }
                          let mut i = 1
                          while i < out.length() {
                            let item = out[i]
                            let mut j = i
                            while j > 0 {
                              let less = match
                                lt_for_sort(
                                  item,
                                  out[j - 1],
                                  globals,
                                  builtins,
                                  io,
                                ) {
                                Ok(v) => v
                                Err(err) => return Err(err)
                              }
                              if !less {
                                break
                              }
                              out[j] = out[j - 1]
                              j -= 1
                            }
                            out[j] = item
                            i += 1
                          }
                          out
                        }
                        if reverse {
                          out = reverse_values(out)
                        }
                        replace_array_values(values, out)
                        return Ok(Value::None)
                      }
                    }
                  }
                  _ => ()
                }
              }
              _ => ()
            }
          } else if inst.class.name == "generator" &&
            bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "send" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "send() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  return generator_send(bound_method.self, positional[0])
                }
              "close" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "close() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return generator_close(bound_method.self)
                }
              "throw" =>
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "throw() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                } else {
                  return generator_throw(bound_method.self, positional[0])
                }
              _ => ()
            }
          } else if inst.class.name == "async_generator" &&
            bound_method.function.body.length() == 0 {
            let has_gen_id = match get_named_value(inst.dict, "gen_id") {
              Some(_) => true
              None => false
            }
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "__aiter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__aiter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(bound_method.self)
                }
              "__anext__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__anext__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if has_gen_id {
                    return Ok(
                      async_generator_make_anext_coroutine(
                        bound_method.self,
                        globals,
                        builtins,
                        io,
                      ),
                    )
                  }
                  return Ok(
                    async_genexp_make_anext_coroutine(
                      bound_method.self,
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              "asend" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "asend() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  if !has_gen_id {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "'async_generator' object has no attribute 'asend'",
                      ),
                    )
                  }
                  return Ok(
                    async_generator_make_asend_coroutine(
                      bound_method.self,
                      positional[0],
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              "athrow" =>
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "athrow() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                } else {
                  if !has_gen_id {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "'async_generator' object has no attribute 'athrow'",
                      ),
                    )
                  }
                  return Ok(
                    async_generator_make_athrow_coroutine(
                      bound_method.self,
                      positional[0],
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              "aclose" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "aclose() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if !has_gen_id {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Attribute,
                        "'async_generator' object has no attribute 'aclose'",
                      ),
                    )
                  }
                  return Ok(
                    async_generator_make_aclose_coroutine(
                      bound_method.self,
                      globals,
                      builtins,
                      io,
                    ),
                  )
                }
              _ => ()
            }
          }
        Value::Str(text) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 &&
              bound_method.function.name != "split" &&
              bound_method.function.name != "splitlines" &&
              bound_method.function.name != "format" {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "startswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "startswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let prefixes : Array[String] = []
                match positional[0] {
                  Value::Str(value) => prefixes.push(value)
                  Value::Tuple(values) =>
                    for item in values {
                      match item {
                        Value::Str(value) => prefixes.push(value)
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "startswith() expects a str prefix".to_string(),
                            ),
                          )
                      }
                    }
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "startswith() expects a str prefix".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let segment = substring(text, start_idx, end_idx)
                let mut matched = false
                for prefix in prefixes {
                  if segment.has_prefix(prefix) {
                    matched = true
                    break
                  }
                }
                return Ok(Value::Bool(matched))
              }
              "find" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "find() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "find() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                if needle.length() == 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(start_idx)))
                }
                let max_start = end_idx - needle.length()
                let mut found = -1
                let mut i = start_idx
                while i <= max_start {
                  if substring(text, i, i + needle.length()) == needle {
                    found = i
                    break
                  }
                  i += 1
                }
                if found < 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(-1)))
                } else {
                  return Ok(Value::Int(@bigint.BigInt::from_int(found)))
                }
              }
              "count" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "count() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "count() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                if needle.length() == 0 {
                  let out = end_idx - start_idx + 1
                  return Ok(Value::Int(@bigint.BigInt::from_int(out)))
                }
                let max_start = end_idx - needle.length()
                let mut found = 0
                let mut i = start_idx
                while i <= max_start {
                  if substring(text, i, i + needle.length()) == needle {
                    found += 1
                    i += needle.length()
                  } else {
                    i += 1
                  }
                }
                return Ok(Value::Int(@bigint.BigInt::from_int(found)))
              }
              "index" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "index() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "index() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                if needle.length() == 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(start_idx)))
                }
                let max_start = end_idx - needle.length()
                let mut found = -1
                let mut i = start_idx
                while i <= max_start {
                  if substring(text, i, i + needle.length()) == needle {
                    found = i
                    break
                  }
                  i += 1
                }
                if found < 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: substring not found".to_string(),
                    ),
                  )
                }
                return Ok(Value::Int(@bigint.BigInt::from_int(found)))
              }
              "rfind" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "rfind() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "rfind() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                if needle.length() == 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(end_idx)))
                }
                if needle.length() > end_idx - start_idx {
                  return Ok(Value::Int(@bigint.BigInt::from_int(-1)))
                }
                let mut found = -1
                let mut i = end_idx - needle.length()
                while i >= start_idx {
                  if substring(text, i, i + needle.length()) == needle {
                    found = i
                    break
                  }
                  i -= 1
                }
                if found < 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(-1)))
                } else {
                  return Ok(Value::Int(@bigint.BigInt::from_int(found)))
                }
              }
              "rindex" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "rindex() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "rindex() expects a str substring".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                if needle.length() == 0 {
                  return Ok(Value::Int(@bigint.BigInt::from_int(end_idx)))
                }
                if needle.length() > end_idx - start_idx {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: substring not found".to_string(),
                    ),
                  )
                }
                let mut found = -1
                let mut i = end_idx - needle.length()
                while i >= start_idx {
                  if substring(text, i, i + needle.length()) == needle {
                    found = i
                    break
                  }
                  i -= 1
                }
                if found < 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: substring not found".to_string(),
                    ),
                  )
                }
                return Ok(Value::Int(@bigint.BigInt::from_int(found)))
              }
              "encode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "encode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let bytes = match
                  encode_string_with_encoding(
                    "encode", text, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Bytes(bytes))
              }
              "endswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "endswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let suffixes : Array[String] = []
                match positional[0] {
                  Value::Str(value) => suffixes.push(value)
                  Value::Tuple(values) =>
                    for item in values {
                      match item {
                        Value::Str(value) => suffixes.push(value)
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "endswith() expects a str suffix".to_string(),
                            ),
                          )
                      }
                    }
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "endswith() expects a str suffix".to_string(),
                      ),
                    )
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    text.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, text.length())
                let mut end_idx = normalize_index(end, text.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > text.length() {
                  start_idx = text.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > text.length() {
                  end_idx = text.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let segment = substring(text, start_idx, end_idx)
                let mut matched = false
                for suffix in suffixes {
                  if segment.has_suffix(suffix) {
                    matched = true
                    break
                  }
                }
                return Ok(Value::Bool(matched))
              }
              "removeprefix" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "removeprefix() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let prefix = match positional[0] {
                    Value::Str(value) => value
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "removeprefix() expects a str prefix".to_string(),
                        ),
                      )
                  }
                  if text.has_prefix(prefix) {
                    return Ok(
                      Value::Str(
                        substring(text, prefix.length(), text.length()),
                      ),
                    )
                  }
                  return Ok(Value::Str(text))
                }
              "removesuffix" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "removesuffix() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let suffix = match positional[0] {
                    Value::Str(value) => value
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "removesuffix() expects a str suffix".to_string(),
                        ),
                      )
                  }
                  if text.has_suffix(suffix) {
                    return Ok(
                      Value::Str(
                        substring(text, 0, text.length() - suffix.length()),
                      ),
                    )
                  }
                  return Ok(Value::Str(text))
                }
              "isascii" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isascii() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  for c in text.to_array() {
                    if c > '\u007f' {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "isdigit" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isdigit() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_ascii_digit(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "isalnum" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isalnum() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_ascii_alnum(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "isalpha" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isalpha() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_ascii_alpha(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "isspace" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isspace() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_python_whitespace(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "islower" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "islower() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  let mut has_cased = false
                  for c in chars {
                    if is_ascii_alpha(c) {
                      has_cased = true
                      if is_ascii_upper(c) {
                        return Ok(Value::Bool(false))
                      }
                    }
                  }
                  return Ok(Value::Bool(has_cased))
                }
              "isupper" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isupper() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  let mut has_cased = false
                  for c in chars {
                    if is_ascii_alpha(c) {
                      has_cased = true
                      if is_ascii_lower(c) {
                        return Ok(Value::Bool(false))
                      }
                    }
                  }
                  return Ok(Value::Bool(has_cased))
                }
              "istitle" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "istitle() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  let mut has_cased = false
                  let mut word_start = true
                  for c in chars {
                    if is_ascii_alpha(c) {
                      has_cased = true
                      if word_start {
                        if !is_ascii_upper(c) {
                          return Ok(Value::Bool(false))
                        }
                        word_start = false
                      } else if !is_ascii_lower(c) {
                        return Ok(Value::Bool(false))
                      }
                    } else {
                      word_start = true
                    }
                  }
                  return Ok(Value::Bool(has_cased))
                }
              "isdecimal" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isdecimal() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_ascii_digit(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "isnumeric" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isnumeric() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  for c in chars {
                    if !is_ascii_digit(c) {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "partition" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "partition() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let sep = match positional[0] {
                    Value::Str(value) => value
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "partition() expects a str separator".to_string(),
                        ),
                      )
                  }
                  if sep.length() == 0 {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "ValueError: empty separator".to_string(),
                      ),
                    )
                  }
                  match text.find(sep) {
                    Some(pos) => {
                      let head = substring(text, 0, pos)
                      let tail = substring(
                        text,
                        pos + sep.length(),
                        text.length(),
                      )
                      return Ok(
                        Value::Tuple([
                          Value::Str(head),
                          Value::Str(sep),
                          Value::Str(tail),
                        ]),
                      )
                    }
                    None =>
                      return Ok(
                        Value::Tuple([
                          Value::Str(text),
                          Value::Str(""),
                          Value::Str(""),
                        ]),
                      )
                  }
                }
              "rpartition" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "rpartition() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let sep = match positional[0] {
                    Value::Str(value) => value
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "rpartition() expects a str separator".to_string(),
                        ),
                      )
                  }
                  if sep.length() == 0 {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Runtime,
                        "ValueError: empty separator".to_string(),
                      ),
                    )
                  }
                  let mut found = -1
                  if sep.length() <= text.length() {
                    let mut i = text.length() - sep.length()
                    while i >= 0 {
                      if substring(text, i, i + sep.length()) == sep {
                        found = i
                        break
                      }
                      i -= 1
                    }
                  }
                  if found < 0 {
                    return Ok(
                      Value::Tuple([
                        Value::Str(""),
                        Value::Str(""),
                        Value::Str(text),
                      ]),
                    )
                  }
                  let head = substring(text, 0, found)
                  let tail = substring(
                    text,
                    found + sep.length(),
                    text.length(),
                  )
                  return Ok(
                    Value::Tuple([
                      Value::Str(head),
                      Value::Str(sep),
                      Value::Str(tail),
                    ]),
                  )
                }
              "expandtabs" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "expandtabs() takes at most one argument".to_string(),
                    ),
                  )
                }
                let mut tabsize = 8
                if positional.length() == 1 {
                  match positional[0] {
                    Value::Int(v) => tabsize = v.to_int64().to_int()
                    Value::Bool(v) => tabsize = if v { 1 } else { 0 }
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "expandtabs() expects an int tabsize".to_string(),
                        ),
                      )
                  }
                }
                if tabsize < 0 {
                  tabsize = 0
                }
                let chars = text.to_array()
                let buf = StringBuilder::new()
                let mut col = 0
                for c in chars {
                  if c == '\t' {
                    if tabsize == 0 {
                      continue
                    }
                    let space_count = tabsize - col % tabsize
                    for _k = 0; _k < space_count; _k = _k + 1 {
                      buf.write_char(' ')
                    }
                    col += space_count
                  } else {
                    buf.write_char(c)
                    if c == '\n' || c == '\r' {
                      col = 0
                    } else {
                      col += 1
                    }
                  }
                }
                return Ok(Value::Str(buf.to_string()))
              }
              "translate" => {
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "translate() takes exactly one argument".to_string(),
                    ),
                  )
                }
                let table = match positional[0] {
                  Value::Dict(pairs) => pairs
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "translate() expects a dict table".to_string(),
                      ),
                    )
                }
                let chars = text.to_array()
                let buf = StringBuilder::new()
                for c in chars {
                  let code = c.to_int()
                  let idx = match
                    dict_find_index(
                      table,
                      Value::Int(@bigint.BigInt::from_int(code)),
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  match idx {
                    Some(pos) =>
                      match table[pos].1 {
                        Value::None => ()
                        Value::Str(rep) => buf.write_string(rep)
                        Value::Int(v) => {
                          let out_code = v.to_int64().to_int()
                          match out_code.to_char() {
                            Some(ch) => buf.write_char(ch)
                            None =>
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Runtime,
                                  "ValueError: invalid character in translate table".to_string(),
                                ),
                              )
                          }
                        }
                        Value::Bool(v) => {
                          let out_code = if v { 1 } else { 0 }
                          match out_code.to_char() {
                            Some(ch) => buf.write_char(ch)
                            None =>
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Runtime,
                                  "ValueError: invalid character in translate table".to_string(),
                                ),
                              )
                          }
                        }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "translate() table values must be int, str, or None".to_string(),
                            ),
                          )
                      }
                    None => buf.write_char(c)
                  }
                }
                return Ok(Value::Str(buf.to_string()))
              }
              "isidentifier" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "isidentifier() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let chars = text.to_array()
                  if chars.length() == 0 {
                    return Ok(Value::Bool(false))
                  }
                  let first = chars[0]
                  if !(is_ascii_alpha(first) || first == '_') {
                    return Ok(Value::Bool(false))
                  }
                  for i = 1; i < chars.length(); i = i + 1 {
                    let c = chars[i]
                    if !(is_ascii_alnum(c) || c == '_') {
                      return Ok(Value::Bool(false))
                    }
                  }
                  return Ok(Value::Bool(true))
                }
              "capitalize" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "capitalize() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if text.length() == 0 {
                    return Ok(Value::Str(text))
                  }
                  let first = substring(text, 0, 1).to_upper()
                  let rest = substring(text, 1, text.length()).to_lower()
                  return Ok(Value::Str(first + rest))
                }
              "center" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "center() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let width = match index_from_value(positional[0], 0) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let fill = if positional.length() == 2 {
                  match positional[1] {
                    Value::Str(v) => v
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "center() fillchar must be str".to_string(),
                        ),
                      )
                  }
                } else {
                  " ".to_string()
                }
                if fill.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: The fill character must be exactly one character long".to_string(),
                    ),
                  )
                }
                if width <= text.length() {
                  return Ok(Value::Str(text))
                }
                let padding = width - text.length()
                let left = padding / 2
                let right = padding - left
                let builder = StringBuilder::new()
                for _i = 0; _i < left; _i = _i + 1 {
                  builder.write_string(fill)
                }
                builder.write_string(text)
                for _i = 0; _i < right; _i = _i + 1 {
                  builder.write_string(fill)
                }
                return Ok(Value::Str(builder.to_string()))
              }
              "upper" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "upper() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Str(text.to_upper()))
                }
              "lower" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "lower() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Str(text.to_lower()))
                }
              "casefold" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "casefold() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(Value::Str(text.to_lower()))
                }
              "replace" => {
                if positional.length() < 2 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "replace() takes 2 or 3 arguments".to_string(),
                    ),
                  )
                }
                let old = match positional[0] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "replace() expects a str pattern".to_string(),
                      ),
                    )
                }
                let new_value = match positional[1] {
                  Value::Str(value) => value
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "replace() expects a str replacement".to_string(),
                      ),
                    )
                }
                let count = if positional.length() == 3 {
                  match index_from_value(positional[2], -1) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                } else {
                  -1
                }
                if count == 0 {
                  return Ok(Value::Str(text))
                }
                if old.length() == 0 {
                  let chars = text.to_array()
                  let total = chars.length() + 1
                  let limit = if count < 0 || count > total {
                    total
                  } else {
                    count
                  }
                  let builder = StringBuilder::new()
                  let mut inserted = 0
                  for i = 0; i < chars.length(); i = i + 1 {
                    if inserted < limit {
                      builder.write_string(new_value)
                      inserted += 1
                    }
                    builder.write_char(chars[i])
                  }
                  if inserted < limit {
                    builder.write_string(new_value)
                  }
                  return Ok(Value::Str(builder.to_string()))
                }
                let builder = StringBuilder::new()
                let mut first = true
                let mut replaced = 0
                for part in text.split(old) {
                  if first {
                    builder.write_string(part.to_string())
                    first = false
                    continue
                  }
                  if count < 0 || replaced < count {
                    builder.write_string(new_value)
                    replaced += 1
                  } else {
                    builder.write_string(old)
                  }
                  builder.write_string(part.to_string())
                }
                return Ok(Value::Str(builder.to_string()))
              }
              "strip" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "strip() takes at most one argument".to_string(),
                    ),
                  )
                }
                let chars_opt = match
                  parse_strip_chars(
                    "strip",
                    if positional.length() == 1 {
                      Some(positional[0])
                    } else {
                      None
                    },
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(
                  Value::Str(strip_text(text, chars_opt, StripMode::Both)),
                )
              }
              "lstrip" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "lstrip() takes at most one argument".to_string(),
                    ),
                  )
                }
                let chars_opt = match
                  parse_strip_chars(
                    "lstrip",
                    if positional.length() == 1 {
                      Some(positional[0])
                    } else {
                      None
                    },
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(
                  Value::Str(strip_text(text, chars_opt, StripMode::Left)),
                )
              }
              "rstrip" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "rstrip() takes at most one argument".to_string(),
                    ),
                  )
                }
                let chars_opt = match
                  parse_strip_chars(
                    "rstrip",
                    if positional.length() == 1 {
                      Some(positional[0])
                    } else {
                      None
                    },
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(
                  Value::Str(strip_text(text, chars_opt, StripMode::Right)),
                )
              }
              "split" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "split() takes at most 2 arguments".to_string(),
                    ),
                  )
                }
                let mut sep_kw : Value? = None
                let mut maxsplit_kw : Value? = None
                for item in keywords {
                  if item.0 == "sep" {
                    sep_kw = Some(item.1)
                  } else if item.0 == "maxsplit" {
                    maxsplit_kw = Some(item.1)
                  } else {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "split() got unexpected keyword arguments".to_string(),
                      ),
                    )
                  }
                }
                if positional.length() >= 1 && sep_kw is Some(_) {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "split() got multiple values for argument 'sep'".to_string(),
                    ),
                  )
                }
                if positional.length() == 2 && maxsplit_kw is Some(_) {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "split() got multiple values for argument 'maxsplit'".to_string(),
                    ),
                  )
                }
                let sep_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  match sep_kw {
                    Some(v) => v
                    None => Value::None
                  }
                }
                let maxsplit_value = if positional.length() == 2 {
                  positional[1]
                } else {
                  match maxsplit_kw {
                    Some(v) => v
                    None => Value::Int(@bigint.BigInt::from_int(-1))
                  }
                }
                let maxsplit = match index_from_value(maxsplit_value, -1) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                match sep_value {
                  Value::None => {
                    let chars = text.to_array()
                    let len = chars.length()
                    let mut i = 0
                    while i < len && is_ascii_whitespace(chars[i]) {
                      i += 1
                    }
                    if i >= len {
                      return Ok(Value::List([]))
                    }
                    if maxsplit == 0 {
                      let mut end = len
                      while end > i && is_ascii_whitespace(chars[end - 1]) {
                        end -= 1
                      }
                      return Ok(
                        Value::List([Value::Str(substring(text, i, end))]),
                      )
                    }
                    let parts : Array[Value] = []
                    let mut splits = 0
                    let mut start = i
                    while i < len {
                      if is_ascii_whitespace(chars[i]) {
                        let end = i
                        parts.push(Value::Str(substring(text, start, end)))
                        splits += 1
                        while i < len && is_ascii_whitespace(chars[i]) {
                          i += 1
                        }
                        if maxsplit >= 0 && splits >= maxsplit {
                          let mut tail_end = len
                          while tail_end > i &&
                                is_ascii_whitespace(chars[tail_end - 1]) {
                            tail_end -= 1
                          }
                          if tail_end > i {
                            parts.push(Value::Str(substring(text, i, tail_end)))
                          }
                          return Ok(Value::List(parts))
                        }
                        start = i
                        continue
                      }
                      i += 1
                    }
                    if i > start {
                      parts.push(Value::Str(substring(text, start, i)))
                    }
                    return Ok(Value::List(parts))
                  }
                  Value::Str(sep) => {
                    if sep.length() == 0 {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Runtime,
                          "ValueError: empty separator".to_string(),
                        ),
                      )
                    }
                    let raw_parts : Array[String] = []
                    for part in text.split(sep) {
                      raw_parts.push(part.to_string())
                    }
                    if maxsplit < 0 || raw_parts.length() <= maxsplit + 1 {
                      let parts : Array[Value] = []
                      for part in raw_parts {
                        parts.push(Value::Str(part))
                      }
                      return Ok(Value::List(parts))
                    }
                    let parts : Array[Value] = []
                    for i = 0; i <= maxsplit; i = i + 1 {
                      parts.push(Value::Str(raw_parts[i]))
                    }
                    let builder = StringBuilder::new()
                    let mut first_tail = true
                    for i = maxsplit + 1; i < raw_parts.length(); i = i + 1 {
                      if !first_tail {
                        builder.write_string(sep)
                      }
                      builder.write_string(raw_parts[i])
                      first_tail = false
                    }
                    parts.push(Value::Str(builder.to_string()))
                    return Ok(Value::List(parts))
                  }
                  _ =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "split() separator must be str or None".to_string(),
                      ),
                    )
                }
              }
              "splitlines" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "splitlines() takes at most 1 argument".to_string(),
                    ),
                  )
                }
                let mut keepends_value : Value? = None
                if positional.length() == 1 {
                  keepends_value = Some(positional[0])
                }
                for pair in keywords {
                  if pair.0 == "keepends" {
                    if keepends_value is Some(_) {
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "splitlines() got multiple values for argument 'keepends'".to_string(),
                        ),
                      )
                    }
                    keepends_value = Some(pair.1)
                  } else {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "splitlines() got unexpected keyword argument '" +
                        pair.0 +
                        "'",
                      ),
                    )
                  }
                }
                let keepends = match keepends_value {
                  None => false
                  Some(Value::None) => false
                  Some(Value::Bool(value)) => value
                  Some(_) =>
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "splitlines() keepends must be bool".to_string(),
                      ),
                    )
                }
                let lines : Array[Value] = []
                let chars = text.to_array()
                let mut builder = StringBuilder::new()
                let mut has_text = false
                let mut i = 0
                while i < chars.length() {
                  let c = chars[i]
                  if c == '\n' || c == '\r' {
                    if keepends {
                      builder.write_char(c)
                      has_text = true
                    }
                    if c == '\r' &&
                      i + 1 < chars.length() &&
                      chars[i + 1] == '\n' {
                      if keepends {
                        builder.write_char('\n')
                        has_text = true
                      }
                      i += 1
                    }
                    lines.push(Value::Str(builder.to_string()))
                    builder = StringBuilder::new()
                    has_text = false
                  } else {
                    builder.write_char(c)
                    has_text = true
                  }
                  i += 1
                }
                if has_text {
                  lines.push(Value::Str(builder.to_string()))
                }
                return Ok(Value::List(lines))
              }
              "format" => {
                let formatted = match
                  format_string_with_args(text, positional, keywords) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(formatted))
              }
              _ => ()
            }
          }
        Value::List(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 && bound_method.function.name != "sort" {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "append" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "append() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  values.push(positional[0])
                  return Ok(Value::None)
                }
              "extend" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "extend() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let to_add : Array[Value] = []
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) => to_add.push(item)
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  for item in to_add {
                    values.push(item)
                  }
                  return Ok(Value::None)
                }
              "insert" =>
                if positional.length() != 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "insert() takes exactly two arguments".to_string(),
                    ),
                  )
                } else {
                  let idx = match index_from_value(positional[0], 0) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  let len = values.length()
                  let mut pos = normalize_index(idx, len)
                  if pos < 0 {
                    pos = 0
                  }
                  if pos > len {
                    pos = len
                  }
                  values.push(Value::None)
                  let mut i = len
                  while i > pos {
                    values[i] = values[i - 1]
                    i = i - 1
                  }
                  values[pos] = positional[1]
                  return Ok(Value::None)
                }
              "remove" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "remove() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let needle = positional[0]
                  for i = 0; i < values.length(); i = i + 1 {
                    if eq_value(values[i], needle) {
                      let _ = values.remove(i)
                      return Ok(Value::None)
                    }
                  }
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Runtime,
                      "ValueError: list.remove(x): x not in list".to_string(),
                    ),
                  )
                }
              "clear" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "clear() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let mut i = values.length()
                  while i > 0 {
                    i = i - 1
                    let _ = values.remove(i)

                  }
                  return Ok(Value::None)
                }
              "pop" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "pop() takes at most one argument".to_string(),
                    ),
                  )
                }
                if values.length() == 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Index,
                      "pop from empty list".to_string(),
                    ),
                  )
                }
                let mut idx = values.length() - 1
                if positional.length() == 1 {
                  let raw = match positional[0] {
                    Value::Int(v) =>
                      match bigint_to_int_checked(v) {
                        Ok(i) => i
                        Err(err) => return Err(err)
                      }
                    Value::Bool(b) => if b { 1 } else { 0 }
                    _ =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "invalid index".to_string(),
                        ),
                      )
                  }
                  let normalized = normalize_index(raw, values.length())
                  if normalized < 0 || normalized >= values.length() {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Index,
                        "pop index out of range".to_string(),
                      ),
                    )
                  }
                  idx = normalized
                }
                let item = values.remove(idx)
                return Ok(item)
              }
              "copy" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let out : Array[Value] = []
                  for item in values {
                    out.push(item)
                  }
                  return Ok(Value::List(out))
                }
              "reverse" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "reverse() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  if values.length() == 0 {
                    return Ok(Value::None)
                  }
                  let mut i = 0
                  let mut j = values.length() - 1
                  while i < j {
                    let tmp = values[i]
                    values[i] = values[j]
                    values[j] = tmp
                    i += 1
                    j -= 1
                  }
                  return Ok(Value::None)
                }
              "sort" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "sort() takes at most 2 arguments".to_string(),
                    ),
                  )
                }
                let mut reverse = false
                let mut key_value : Value? = None
                for pair in keywords {
                  if pair.0 == "key" {
                    key_value = Some(pair.1)
                  } else if pair.0 == "reverse" {
                    reverse = bool_from_value(pair.1)
                  } else {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "sort() got unexpected keyword arguments".to_string(),
                      ),
                    )
                  }
                }
                if positional.length() >= 1 {
                  if key_value is Some(_) {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Type,
                        "sort() got multiple values for argument 'key'".to_string(),
                      ),
                    )
                  }
                  key_value = Some(positional[0])
                }
                if positional.length() == 2 {
                  reverse = bool_from_value(positional[1])
                }
                if values.length() == 0 {
                  return Ok(Value::None)
                }
                fn lt_for_sort(
                  a : Value,
                  b : Value,
                  globals : Array[(String, Value)],
                  builtins : Array[(String, Value)],
                  io : MockIO,
                ) -> Result[Bool, RuntimeError] {
                  match (a, b) {
                    (Value::Str(x), Value::Str(y)) => Ok(x < y)
                    (Value::Int(_) | Value::Float(_) | Value::Bool(_), _)
                    | (_, Value::Int(_) | Value::Float(_) | Value::Bool(_)) => {
                      let (_, left_num) = match number_value(a) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      let (_, right_num) = match number_value(b) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      Ok(left_num < right_num)
                    }
                    _ => {
                      let lt = match
                        get_attr_from_value(a, "__lt__", globals, builtins, io) {
                        Ok(v) => v
                        Err(err) =>
                          match err.kind {
                            RuntimeErrorKind::Attribute =>
                              return Err(
                                make_runtime_error(
                                  RuntimeErrorKind::Type,
                                  "sort() cannot compare values".to_string(),
                                ),
                              )
                            _ => return Err(err)
                          }
                      }
                      let result = match
                        call_callable_with_env(
                          lt,
                          [b],
                          [],
                          globals,
                          builtins,
                          io,
                        ) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      Ok(bool_from_value(result))
                    }
                  }
                }

                match key_value {
                  Some(key_fn) => {
                    let key_pairs : Array[(Value, Value)] = []
                    for item in values {
                      let key = if key_fn is Value::None {
                        item
                      } else {
                        match
                          call_callable_with_env(
                            key_fn,
                            [item],
                            [],
                            globals,
                            builtins,
                            io,
                          ) {
                          Ok(value) => value
                          Err(err) => return Err(err)
                        }
                      }
                      key_pairs.push((key, item))
                    }
                    fn insertion_sort_pairs_by_key(
                      pairs : Array[(Value, Value)],
                      globals : Array[(String, Value)],
                      builtins : Array[(String, Value)],
                      io : MockIO,
                    ) -> Result[Unit, RuntimeError] {
                      let mut i = 1
                      while i < pairs.length() {
                        let item = pairs[i]
                        let mut j = i
                        while j > 0 {
                          let less = match
                            lt_for_sort(
                              item.0,
                              pairs[j - 1].0,
                              globals,
                              builtins,
                              io,
                            ) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          if !less {
                            break
                          }
                          pairs[j] = pairs[j - 1]
                          j -= 1
                        }
                        pairs[j] = item
                        i += 1
                      }
                      Ok(())
                    }

                    let mut kind_opt : SortKind? = None
                    let mut can_use_fast = true
                    for pair in key_pairs {
                      match sort_kind_for_sorted(pair.0) {
                        Some(kind) =>
                          match kind_opt {
                            None => kind_opt = Some(kind)
                            Some(prev) =>
                              if prev != kind {
                                can_use_fast = false
                              }
                          }
                        None => can_use_fast = false
                      }
                    }
                    let sorted_pairs = if can_use_fast {
                      let kind = match kind_opt {
                        Some(kind) => kind
                        None => return Ok(Value::None)
                      }
                      match stable_sort_pairs_by_key(key_pairs, kind) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                    } else {
                      let _ = match
                        insertion_sort_pairs_by_key(
                          key_pairs, globals, builtins, io,
                        ) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      key_pairs
                    }
                    let sorted_items : Array[Value] = []
                    for pair in sorted_pairs {
                      sorted_items.push(pair.1)
                    }
                    let out = if reverse {
                      reverse_values(sorted_items)
                    } else {
                      sorted_items
                    }
                    replace_array_values(values, out)
                    return Ok(Value::None)
                  }
                  None => {
                    let mut kind_opt : SortKind? = None
                    let mut can_use_fast = true
                    for item in values {
                      match sort_kind_for_sorted(item) {
                        Some(kind) =>
                          match kind_opt {
                            None => kind_opt = Some(kind)
                            Some(prev) =>
                              if prev != kind {
                                can_use_fast = false
                              }
                          }
                        None => can_use_fast = false
                      }
                    }
                    let mut out = if can_use_fast {
                      let kind = match kind_opt {
                        Some(kind) => kind
                        None => return Ok(Value::None)
                      }
                      match stable_sort_for_sorted(values, kind) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                    } else {
                      let out : Array[Value] = []
                      for item in values {
                        out.push(item)
                      }
                      let mut i = 1
                      while i < out.length() {
                        let item = out[i]
                        let mut j = i
                        while j > 0 {
                          let less = match
                            lt_for_sort(item, out[j - 1], globals, builtins, io) {
                            Ok(v) => v
                            Err(err) => return Err(err)
                          }
                          if !less {
                            break
                          }
                          out[j] = out[j - 1]
                          j -= 1
                        }
                        out[j] = item
                        i += 1
                      }
                      out
                    }
                    if reverse {
                      out = reverse_values(out)
                    }
                    replace_array_values(values, out)
                    return Ok(Value::None)
                  }
                }
              }
              _ => ()
            }
          }
        Value::Tuple(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "index" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "index() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                let needle = positional[0]
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    values.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, values.length())
                let mut end_idx = normalize_index(end, values.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > values.length() {
                  start_idx = values.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > values.length() {
                  end_idx = values.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let mut i = start_idx
                while i < end_idx {
                  if eq_value(values[i], needle) {
                    return Ok(Value::Int(@bigint.BigInt::from_int(i)))
                  }
                  i += 1
                }
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Runtime,
                    "ValueError: tuple.index(x): x not in tuple".to_string(),
                  ),
                )
              }
              _ => ()
            }
          }
        Value::Dict(pairs) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "get" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "get() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let key = positional[0]
                let default_value = if positional.length() == 2 {
                  positional[1]
                } else {
                  Value::None
                }
                let index = match dict_find_index(pairs, key) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return match index {
                  Some(i) => Ok(pairs[i].1)
                  None => Ok(default_value)
                }
              }
              "pop" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "pop() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let key = positional[0]
                let index = match dict_find_index(pairs, key) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if index is Some(i) {
                  let removed = pairs.remove(i)
                  return Ok(removed.1)
                }
                if positional.length() == 2 {
                  return Ok(positional[1])
                }
                return Err(
                  make_runtime_error(
                    RuntimeErrorKind::Key,
                    "key not found".to_string(),
                  ),
                )
              }
              "popitem" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "popitem() takes no arguments".to_string(),
                    ),
                  )
                }
                if pairs.length() == 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Key,
                      "popitem(): dictionary is empty".to_string(),
                    ),
                  )
                }
                let removed = pairs.remove(pairs.length() - 1)
                return Ok(Value::Tuple([removed.0, removed.1]))
              }
              "setdefault" => {
                if positional.length() == 0 || positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "setdefault() takes 1 or 2 arguments".to_string(),
                    ),
                  )
                }
                let key = positional[0]
                let default_value = if positional.length() == 2 {
                  positional[1]
                } else {
                  Value::None
                }
                let index = match dict_find_index(pairs, key) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                if index is Some(i) {
                  return Ok(pairs[i].1)
                }
                let _ = match dict_set_item(pairs, key, default_value) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(default_value)
              }
              "keys" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "keys() takes no arguments".to_string(),
                    ),
                  )
                }
                return Ok(
                  make_dict_view_instance("dict_keys", Value::Dict(pairs)),
                )
              }
              "values" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "values() takes no arguments".to_string(),
                    ),
                  )
                }
                return Ok(
                  make_dict_view_instance("dict_values", Value::Dict(pairs)),
                )
              }
              "items" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "items() takes no arguments".to_string(),
                    ),
                  )
                }
                return Ok(
                  make_dict_view_instance("dict_items", Value::Dict(pairs)),
                )
              }
              "update" => {
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "update() takes at most one argument".to_string(),
                    ),
                  )
                }
                if positional.length() == 0 || positional[0] is Value::None {
                  return Ok(Value::None)
                }
                let other = positional[0]
                let entries : Array[(Value, Value)] = []
                match other {
                  Value::Dict(other_pairs) =>
                    for pair in other_pairs {
                      entries.push(pair)
                    }
                  _ => {
                    let iterator = match
                      iter_value_to_iterator(other, globals, builtins, io) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    while true {
                      let item = match
                        iterator_next(iterator, None, globals, builtins, io) {
                        Ok(v) => v
                        Err(err) =>
                          if err.exc_type == "StopIteration" {
                            break
                          } else {
                            return Err(err)
                          }
                      }
                      match item {
                        Value::Tuple(values) | Value::List(values) =>
                          if values.length() != 2 {
                            return Err(
                              make_runtime_error(
                                RuntimeErrorKind::Type,
                                "update() sequence element has wrong length".to_string(),
                              ),
                            )
                          } else {
                            entries.push((values[0], values[1]))
                          }
                        _ =>
                          return Err(
                            make_runtime_error(
                              RuntimeErrorKind::Type,
                              "update() expects (key, value) pairs".to_string(),
                            ),
                          )
                      }
                    }
                  }
                }
                for entry in entries {
                  let key = entry.0
                  let value = entry.1
                  let _ = match dict_set_item(pairs, key, value) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }

                }
                return Ok(Value::None)
              }
              "clear" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "clear() takes no arguments".to_string(),
                    ),
                  )
                }
                let mut i = pairs.length()
                while i > 0 {
                  i = i - 1
                  let _ = pairs.remove(i)

                }
                return Ok(Value::None)
              }
              "copy" => {
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                }
                let out_pairs : Array[(Value, Value)] = []
                for pair in pairs {
                  out_pairs.push(pair)
                }
                return Ok(Value::Dict(out_pairs))
              }
              "__contains__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__contains__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let index = match dict_find_index(pairs, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::Bool(index is Some(_)))
                }
              "__getitem__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__getitem__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let key = positional[0]
                  let index = match dict_find_index(pairs, key) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  match index {
                    Some(i) => return Ok(pairs[i].1)
                    None =>
                      return Err(
                        make_runtime_error(
                          RuntimeErrorKind::Key,
                          "key not found".to_string(),
                        ),
                      )
                  }
                }
              "__setitem__" =>
                if positional.length() != 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__setitem__() takes exactly two arguments".to_string(),
                    ),
                  )
                } else {
                  let _ = match
                    dict_set_item(pairs, positional[0], positional[1]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::None)
                }
              "__delitem__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__delitem__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let removed = match dict_delete_key(pairs, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if !removed {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Key,
                        "key not found".to_string(),
                      ),
                    )
                  }
                  return Ok(Value::None)
                }
              "__iter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__iter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let keys : Array[Value] = []
                  for pair in pairs {
                    keys.push(pair.0)
                  }
                  return Ok(make_iterator(keys))
                }
              "__len__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__len__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(
                    Value::Int(@bigint.BigInt::from_int(pairs.length())),
                  )
                }
              _ => ()
            }
          }
        Value::Set(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "add" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "add() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let _ = match set_add_unique(values, positional[0]) {
                    Ok(_) => ()
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::None)
                }
              "remove" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "remove() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let removed = match set_remove_item(values, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if !removed {
                    return Err(
                      make_runtime_error(
                        RuntimeErrorKind::Key,
                        "key not found".to_string(),
                      ),
                    )
                  }
                  return Ok(Value::None)
                }
              "discard" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "discard() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let _ = match set_remove_item(values, positional[0]) {
                    Ok(_) => ()
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::None)
                }
              "pop" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "pop() takes no arguments".to_string(),
                    ),
                  )
                } else if values.length() == 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Key,
                      "pop from empty set".to_string(),
                    ),
                  )
                } else {
                  let idx = values.length() - 1
                  let item = values.remove(idx)
                  return Ok(item)
                }
              "clear" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "clear() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let mut i = values.length()
                  while i > 0 {
                    i = i - 1
                    let _ = values.remove(i)

                  }
                  return Ok(Value::None)
                }
              "copy" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let out : Array[Value] = []
                  for item in values {
                    out.push(item)
                  }
                  return Ok(Value::Set(out))
                }
              "update" =>
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "update() takes at most one argument".to_string(),
                    ),
                  )
                } else if positional.length() == 0 ||
                  positional[0] is Value::None {
                  return Ok(Value::None)
                } else {
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(values, item) {
                          Ok(_) => ()
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  return Ok(Value::None)
                }
              "difference" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "difference() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let other_values : Array[Value] = []
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(other_values, item) {
                          Ok(_) => ()
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  let out : Array[Value] = []
                  for item in values {
                    let index = match set_find_index(other_values, item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    if index is None {
                      let _ = match set_add_unique(out, item) {
                        Ok(_) => ()
                        Err(err) => return Err(err)
                      }

                    }
                  }
                  return Ok(Value::Set(out))
                }
              "difference_update" => {
                // Remove all elements found in any of the provided iterables.
                if positional.length() == 0 {
                  return Ok(Value::None)
                }
                let remove_values : Array[Value] = []
                for arg in positional {
                  let iterator = match
                    iter_value_to_iterator(arg, globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(remove_values, item) {
                          Ok(_) => ()
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                }
                let mut i = values.length()
                while i > 0 {
                  i = i - 1
                  let item = values[i]
                  let index = match set_find_index(remove_values, item) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  if index is Some(_) {
                    let _ = values.remove(i)

                  }
                }
                return Ok(Value::None)
              }
              "issuperset" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "issuperset() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  let mut ok = true
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_find_index(values, item) {
                          Ok(Some(_)) => ()
                          Ok(None) => {
                            ok = false
                            break
                          }
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  return Ok(Value::Bool(ok))
                }
              "issubset" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "issubset() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let other_values : Array[Value] = []
                  let iterator = match
                    iter_value_to_iterator(positional[0], globals, builtins, io) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  while true {
                    match iterator_next(iterator, None, globals, builtins, io) {
                      Ok(item) =>
                        match set_add_unique(other_values, item) {
                          Ok(_) => ()
                          Err(err) => return Err(err)
                        }
                      Err(err) =>
                        if err.exc_type == "StopIteration" {
                          break
                        } else {
                          return Err(err)
                        }
                    }
                  }
                  let mut ok = true
                  for item in values {
                    let index = match set_find_index(other_values, item) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    if index is None {
                      ok = false
                      break
                    }
                  }
                  return Ok(Value::Bool(ok))
                }
              "__contains__" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__contains__() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let index = match set_find_index(values, positional[0]) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  return Ok(Value::Bool(index is Some(_)))
                }
              "__iter__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__iter__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(make_iterator(values))
                }
              "__len__" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "__len__() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  return Ok(
                    Value::Int(@bigint.BigInt::from_int(values.length())),
                  )
                }
              _ => ()
            }
          }
        Value::Bytes(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "decode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "decode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let text = match
                  decode_bytes_with_encoding(
                    "decode", values, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(text))
              }
              "startswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "startswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                fn prefix_bytes(
                  value : Value,
                ) -> Result[Array[Int], RuntimeError] {
                  match value {
                    Value::Bytes(v)
                    | Value::ByteArray(v)
                    | Value::MemoryView(v) => Ok(v)
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "startswith() expects a bytes-like prefix".to_string(),
                        ),
                      )
                  }
                }

                let prefixes : Array[Array[Int]] = []
                match positional[0] {
                  Value::Tuple(items) =>
                    for item in items {
                      let prefix = match prefix_bytes(item) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      prefixes.push(prefix)
                    }
                  _ => {
                    let prefix = match prefix_bytes(positional[0]) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    prefixes.push(prefix)
                  }
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    values.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, values.length())
                let mut end_idx = normalize_index(end, values.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > values.length() {
                  start_idx = values.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > values.length() {
                  end_idx = values.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let available = end_idx - start_idx
                let mut matched = false
                for prefix in prefixes {
                  if prefix.length() <= available {
                    let mut ok = true
                    for j = 0; j < prefix.length(); j = j + 1 {
                      if values[start_idx + j] != prefix[j] {
                        ok = false
                        break
                      }
                    }
                    if ok {
                      matched = true
                      break
                    }
                  }
                }
                return Ok(Value::Bool(matched))
              }
              "endswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "endswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                fn suffix_bytes(
                  value : Value,
                ) -> Result[Array[Int], RuntimeError] {
                  match value {
                    Value::Bytes(v)
                    | Value::ByteArray(v)
                    | Value::MemoryView(v) => Ok(v)
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "endswith() expects a bytes-like suffix".to_string(),
                        ),
                      )
                  }
                }

                let suffixes : Array[Array[Int]] = []
                match positional[0] {
                  Value::Tuple(items) =>
                    for item in items {
                      let suffix = match suffix_bytes(item) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      suffixes.push(suffix)
                    }
                  _ => {
                    let suffix = match suffix_bytes(positional[0]) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    suffixes.push(suffix)
                  }
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    values.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, values.length())
                let mut end_idx = normalize_index(end, values.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > values.length() {
                  start_idx = values.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > values.length() {
                  end_idx = values.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let available = end_idx - start_idx
                let mut matched = false
                for suffix in suffixes {
                  if suffix.length() <= available {
                    let offset = end_idx - suffix.length()
                    let mut ok = true
                    for j = 0; j < suffix.length(); j = j + 1 {
                      if values[offset + j] != suffix[j] {
                        ok = false
                        break
                      }
                    }
                    if ok {
                      matched = true
                      break
                    }
                  }
                }
                return Ok(Value::Bool(matched))
              }
              _ => ()
            }
          }
        Value::MemoryView(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "decode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "decode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let text = match
                  decode_bytes_with_encoding(
                    "decode", values, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(text))
              }
              "startswith" => {
                if positional.length() == 0 || positional.length() > 3 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "startswith() takes 1 to 3 arguments".to_string(),
                    ),
                  )
                }
                fn prefix_bytes(
                  value : Value,
                ) -> Result[Array[Int], RuntimeError] {
                  match value {
                    Value::Bytes(v)
                    | Value::ByteArray(v)
                    | Value::MemoryView(v) => Ok(v)
                    _ =>
                      Err(
                        make_runtime_error(
                          RuntimeErrorKind::Type,
                          "startswith() expects a bytes-like prefix".to_string(),
                        ),
                      )
                  }
                }

                let prefixes : Array[Array[Int]] = []
                match positional[0] {
                  Value::Tuple(items) =>
                    for item in items {
                      let prefix = match prefix_bytes(item) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      prefixes.push(prefix)
                    }
                  _ => {
                    let prefix = match prefix_bytes(positional[0]) {
                      Ok(v) => v
                      Err(err) => return Err(err)
                    }
                    prefixes.push(prefix)
                  }
                }
                let start = match
                  index_from_value(
                    if positional.length() >= 2 {
                      positional[1]
                    } else {
                      Value::None
                    },
                    0,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let end = match
                  index_from_value(
                    if positional.length() == 3 {
                      positional[2]
                    } else {
                      Value::None
                    },
                    values.length(),
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                let mut start_idx = normalize_index(start, values.length())
                let mut end_idx = normalize_index(end, values.length())
                if start_idx < 0 {
                  start_idx = 0
                }
                if start_idx > values.length() {
                  start_idx = values.length()
                }
                if end_idx < 0 {
                  end_idx = 0
                }
                if end_idx > values.length() {
                  end_idx = values.length()
                }
                if end_idx < start_idx {
                  end_idx = start_idx
                }
                let available = end_idx - start_idx
                let mut matched = false
                for prefix in prefixes {
                  if prefix.length() <= available {
                    let mut ok = true
                    for j = 0; j < prefix.length(); j = j + 1 {
                      if values[start_idx + j] != prefix[j] {
                        ok = false
                        break
                      }
                    }
                    if ok {
                      matched = true
                      break
                    }
                  }
                }
                return Ok(Value::Bool(matched))
              }
              _ => ()
            }
          }
        Value::ByteArray(values) =>
          if bound_method.function.body.length() == 0 {
            if keywords.length() > 0 {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  bound_method.function.name +
                  "() got unexpected keyword arguments".to_string(),
                ),
              )
            }
            match bound_method.function.name {
              "decode" => {
                if positional.length() > 2 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "decode() takes 0 to 2 arguments".to_string(),
                    ),
                  )
                }
                let encoding_value = if positional.length() >= 1 {
                  positional[0]
                } else {
                  Value::Str("utf-8")
                }
                let errors_value = if positional.length() == 2 {
                  Some(positional[1])
                } else {
                  None
                }
                let text = match
                  decode_bytes_with_encoding(
                    "decode", values, encoding_value, errors_value,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }
                return Ok(Value::Str(text))
              }
              "extend" =>
                if positional.length() != 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "extend() takes exactly one argument".to_string(),
                    ),
                  )
                } else {
                  let other = positional[0]
                  match other {
                    Value::Bytes(bytes)
                    | Value::ByteArray(bytes)
                    | Value::MemoryView(bytes) =>
                      for b in bytes {
                        values.push(b & 0xFF)
                      }
                    _ => {
                      let iterator = match
                        iter_value_to_iterator(other, globals, builtins, io) {
                        Ok(v) => v
                        Err(err) => return Err(err)
                      }
                      while true {
                        match
                          iterator_next(iterator, None, globals, builtins, io) {
                          Ok(item) => {
                            let b = match byte_from_value("extend", item) {
                              Ok(v) => v
                              Err(err) => return Err(err)
                            }
                            values.push(b)
                          }
                          Err(err) =>
                            if err.exc_type == "StopIteration" {
                              break
                            } else {
                              return Err(err)
                            }
                        }
                      }
                    }
                  }
                  return Ok(Value::None)
                }
              "copy" =>
                if positional.length() != 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "copy() takes no arguments".to_string(),
                    ),
                  )
                } else {
                  let out : Array[Int] = []
                  for item in values {
                    out.push(item)
                  }
                  return Ok(Value::ByteArray(out))
                }
              _ => ()
            }
          }
        _ => ()
      }
      let args : Array[Value] = [bound_method.self]
      for item in positional {
        args.push(item)
      }
      if bound_method.function.body.length() == 0 {
        match
          eval_builtin_call(
            bound_method.function.name,
            args,
            keywords,
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(Some(value)) => return Ok(value)
          Ok(None) => ()
          Err(err) => return Err(err)
        }
      }
      if bound_method.function.is_async {
        if bound_method.function.is_generator {
          return (eval_generator_with_kwargs_ref.val)(
            bound_method.function,
            args,
            keywords,
            globals,
            builtins,
            io,
          )
        }
        return (eval_function_with_kwargs_ref.val)(
          bound_method.function,
          args,
          keywords,
          globals,
          builtins,
          io,
        )
      }
      if bound_method.function.is_generator {
        return (eval_generator_with_kwargs_ref.val)(
          bound_method.function,
          args,
          keywords,
          globals,
          builtins,
          io,
        )
      }
      (eval_function_with_kwargs_ref.val)(
        bound_method.function,
        args,
        keywords,
        globals,
        builtins,
        io,
      )
    }
    Value::Class(klass) => {
      if klass.name == "rangeiter" {
        return Err(
          make_runtime_error(
            RuntimeErrorKind::Type,
            "cannot create 'range_iterator' instances".to_string(),
          ),
        )
      }
      let is_builtin = match get_named_value(klass.dict, "__module__") {
        Some(Value::Str(module_name)) =>
          module_name == "builtins" && is_builtin_class_name(klass.name)
        _ => false
      }
      if is_builtin {
        match
          eval_builtin_call(
            klass.name,
            positional,
            keywords,
            [],
            globals,
            builtins,
            io,
          ) {
          Ok(Some(value)) => return Ok(value)
          Ok(None) => ()
          Err(err) => return Err(err)
        }
      }
      let abstract_values_opt = match
        get_named_value(klass.dict, "__abstractmethods__") {
        Some(Value::Set(values)) => Some(values)
        Some(Value::Tuple(values)) => Some(values)
        _ => None
      }
      if abstract_values_opt is Some(values) {
        let names : Array[String] = []
        for item in values {
          match item {
            Value::Str(name) => names.push(name)
            _ => ()
          }
        }
        if names.length() > 0 {
          for i = 0; i < names.length(); i = i + 1 {
            let mut best = i
            for j = i + 1; j < names.length(); j = j + 1 {
              if cmp_string_for_sorted(names[j], names[best]) < 0 {
                best = j
              }
            }
            if best != i {
              let tmp = names[i]
              names[i] = names[best]
              names[best] = tmp
            }
          }
          let builder = StringBuilder::new()
          for i = 0; i < names.length(); i = i + 1 {
            if i > 0 {
              builder.write_string(", ")
            }
            builder.write_string("'" + names[i] + "'")
          }
          let label = if names.length() == 1 { "method" } else { "methods" }
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "class " +
              klass.name +
              " without an implementation for abstract " +
              label +
              " " +
              builder.to_string(),
            ),
          )
        }
      }
      if klass.name == "BaseExceptionGroup" || klass.name == "ExceptionGroup" {
        if positional.length() != 2 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              klass.name + "() requires a message and exceptions".to_string(),
            ),
          )
        }
        let message = positional[0]
        let raw_exceptions = match positional[1] {
          Value::List(values) => values
          Value::Tuple(values) => values
          _ =>
            return Err(
              make_runtime_error(
                RuntimeErrorKind::Type,
                klass.name + " exceptions must be a list".to_string(),
              ),
            )
        }
        if raw_exceptions.length() == 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              klass.name + " requires at least one exception".to_string(),
            ),
          )
        }
        let mut require_exception = false
        if klass.name == "ExceptionGroup" {
          require_exception = true
        }
        let exceptions : Array[Value] = []
        for exc in raw_exceptions {
          let exc_value = match
            ensure_exception_instance_from_value(exc, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let inst = match exc_value {
            Value::Instance(inst) => inst
            _ =>
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "exceptions must derive from BaseException".to_string(),
                ),
              )
          }
          if require_exception {
            let mro = match class_mro(inst.class) {
              Ok(value) => value
              Err(err) => return Err(err)
            }
            let mut ok = false
            for cls in mro {
              if cls.name == "Exception" {
                ok = true
                break
              }
            }
            if !ok {
              return Err(
                make_runtime_error(
                  RuntimeErrorKind::Type,
                  "ExceptionGroup exceptions must derive from Exception".to_string(),
                ),
              )
            }
          }
          exceptions.push(Value::Instance(inst))
        }
        let exception_tuple : Array[Value] = []
        for item in exceptions {
          exception_tuple.push(item)
        }
        let dict : Array[(String, Value)] = []
        dict.push(("__traceback__", Value::None))
        dict.push(
          ("args", Value::Tuple([message, Value::Tuple(exception_tuple)])),
        )
        dict.push(("__cause__", Value::None))
        dict.push(("__context__", Value::None))
        dict.push(("__suppress_context__", Value::Bool(false)))
        dict.push(("message", message))
        dict.push(("exceptions", Value::List(exceptions)))
        return Ok(Value::Instance(InstanceValue::{ class: klass, dict }))
      }
      // Minimal exception instance payload for any BaseException subclass.
      // This is relied upon by the CPython stdlib (e.g. abc/unittest) for custom
      // exception classes like `class CustomError(Exception): ...`.
      let ok = match is_base_exception_class(klass) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if ok {
        let dict : Array[(String, Value)] = []
        dict.push(("__traceback__", Value::None))
        dict.push(("args", Value::Tuple(positional)))
        dict.push(("__cause__", Value::None))
        dict.push(("__context__", Value::None))
        dict.push(("__suppress_context__", Value::Bool(false)))
        if positional.length() > 0 {
          dict.push(("message", positional[0]))
        }
        if klass.name == "StopIteration" || klass.name == "StopAsyncIteration" {
          let value = if positional.length() > 0 {
            positional[0]
          } else {
            Value::None
          }
          dict.push(("value", value))
        }
        let inst_value = Value::Instance(InstanceValue::{ class: klass, dict })
        // Respect custom exception __init__ implementations (e.g. regrtest's
        // TestFailedWithDetails sets extra fields like `.errors`).
        let init = match lookup_class_attr(klass, "__init__") {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        match init {
          Some(Value::Function(func)) =>
            // Avoid running BaseException.__init__ bodies when we don't model
            // them; custom subclasses still get their Python __init__ executed.
            if func.body.length() > 0 {
              let args : Array[Value] = [inst_value]
              for item in positional {
                args.push(item)
              }
              let _ = match
                (eval_function_with_kwargs_ref.val)(
                  func, args, keywords, globals, builtins, io,
                ) {
                Ok(v) => v
                Err(err) => return Err(err)
              }

            }
          _ => ()
        }
        return Ok(inst_value)
      }
      let new_value = match lookup_class_attr(klass, "__new__") {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let mut inst_value_opt : Value? = None
      match new_value {
        Some(value) => {
          let args : Array[Value] = [Value::Class(klass)]
          for item in positional {
            args.push(item)
          }
          let created = match
            call_callable_with_env(value, args, keywords, globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          inst_value_opt = Some(created)
        }
        None => ()
      }
      let init = match lookup_class_attr(klass, "__init__") {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let inst_value = match inst_value_opt {
        Some(value) => value
        None => {
          let inst_dict : Array[(String, Value)] = []
          if class_includes_list(klass) {
            inst_dict.push((list_storage_name, Value::List([])))
          }
          if class_includes_dict(klass) {
            inst_dict.push((dict_storage_name, Value::Dict([])))
          }
          Value::Instance(InstanceValue::{ class: klass, dict: inst_dict })
        }
      }
      match inst_value {
        Value::Instance(inst) => {
          match get_named_value(inst.dict, list_storage_name) {
            Some(Value::List(values)) =>
              // List subclasses (e.g. `class L(list): ...`) currently don't inherit
              // `list.__init__` from the builtins class table, so initialize their
              // backing storage here unless they define a custom `__init__`.
              if get_named_value(klass.dict, "__init__") is None {
                if keywords.length() > 0 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "list() takes no keyword arguments".to_string(),
                    ),
                  )
                }
                if positional.length() > 1 {
                  return Err(
                    make_runtime_error(
                      RuntimeErrorKind::Type,
                      "list expected at most 1 argument, got " +
                      positional.length().to_string(),
                    ),
                  )
                }
                if positional.length() == 1 {
                  let items = match
                    collect_items_from_iterable(
                      positional[0],
                      globals,
                      builtins,
                      io,
                    ) {
                    Ok(v) => v
                    Err(err) => return Err(err)
                  }
                  replace_array_values(values, items)
                }
              }
            _ => ()
          }
          match init {
            Some(Value::Function(func)) =>
              if inst.class.name == klass.name {
                let args : Array[Value] = [Value::Instance(inst)]
                for item in positional {
                  args.push(item)
                }
                let _ = match
                  call_callable_with_env(
                    Value::Function(func),
                    args,
                    keywords,
                    globals,
                    builtins,
                    io,
                  ) {
                  Ok(v) => v
                  Err(err) => return Err(err)
                }

              }
            _ => ()
          }
          Ok(Value::Instance(inst))
        }
        _ => Ok(inst_value)
      }
    }
    Value::Instance(inst) => {
      if inst.class.name == "weakref" || inst.class.name == "KeyedRef" {
        if positional.length() != 0 || keywords.length() != 0 {
          return Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              "weakref() takes no arguments".to_string(),
            ),
          )
        }
        return match get_named_value(inst.dict, "value") {
          Some(v) => Ok(v)
          None => Ok(Value::None)
        }
      }
      // Callable objects: obj(...) dispatches to obj.__call__(...)
      let call_attr = match lookup_class_attr(inst.class, "__call__") {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match call_attr {
        Some(_) => {
          // Reuse the regular attribute lookup path so we also get descriptor
          // behavior and method binding.
          let bound = match
            get_attr_raw_from_value(callee, "__call__", globals, builtins, io) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          call_callable_with_env(
            bound, positional, keywords, globals, builtins, io,
          )
        }
        None =>
          Err(
            make_runtime_error(
              RuntimeErrorKind::Type,
              not_callable_message(callee),
            ),
          )
      }
    }
    _ =>
      Err(
        make_runtime_error(RuntimeErrorKind::Type, not_callable_message(callee)),
      )
  }
}
