package imgui

import "core:c"
import "core:math"
import "core:time"
import "core:slice"
import "core:reflect"
import "base:runtime"
import "core:mem"
import "core:fmt"
import "core:strings"
import "base:intrinsics"


/*
    A combo box that allows the user to select a key from a map.
    Technically, you should be able to use this with any map type, 
    however I would only recommend using it for simple things like string, int, or enum.
    
    TODO: implement a dynamic version
*/
ComboHash :: proc(
    label:              string, 
    _map:               ^$T/map[$K]$V, 
    selected:           ^K, 
    combo_flags:        ComboFlags      = {}, 
    selectable_flags:   SelectableFlags = {},
) {
    clabel := strings.clone_to_cstring(label, context.temp_allocator)
    
    selected_key_string := fmt.ctprintf("%v", selected)
    if BeginCombo(clabel, selected_key_string, combo_flags) {
        for k in _map {
            key_string := fmt.ctprintf("%v\x00", k)
            if SelectableEx(key_string, selected^ == k, selectable_flags, {}) {
                selected^ = k
            }
        }
        EndCombo()
    }
}

ComboEnum :: proc(
    label:              string, 
    value:              ^$T, 
    combo_flags:        ComboFlags      = {}, 
    selectable_flags:   SelectableFlags = {}
) where intrinsics.type_is_enum(T) {
    clabel := strings.clone_to_cstring(label, context.temp_allocator)
    values := reflect.enum_field_values(T)
    names  := reflect.enum_field_names(T)
    current_value_index := slice.linear_search(values, auto_cast value^) or_else 0 // Could we use binary search? need to find out if values are always ordered...
    current_value_name  := names[current_value_index]
    
    if BeginCombo(clabel, strings.unsafe_string_to_cstring(current_value_name), combo_flags) {
        for i in 0..<len(values) {
            if Selectable(strings.unsafe_string_to_cstring(names[i]), value^ == T(values[i]), selectable_flags, {}) {
                value^ = T(values[i])
            }
        }
        EndCombo()
    }
}

// If the given type is not an enum, the procedure will do nothing and return
ComboEnumDynamic :: proc(
    label:              string, 
    value:              any, 
    combo_flags:        ComboFlags      = {}, 
    selectable_flags:   SelectableFlags = {}
) {
    ti_base := runtime.type_info_base(type_info_of(value.id))
    ti_enum, ok := ti_base.variant.(runtime.Type_Info_Enum)
    if !ok do return
    
    enum_value : runtime.Type_Info_Enum_Value
    switch ti_base.size {
      case 1: enum_value = auto_cast ((^u8 )(value.data))^
      case 2: enum_value = auto_cast ((^u16)(value.data))^
      case 4: enum_value = auto_cast ((^u32)(value.data))^
      case 8: enum_value = auto_cast ((^u64)(value.data))^
    }
    
    current_value_index := slice.linear_search(ti_enum.values, enum_value) or_else 0 
    current_value_name  := ti_enum.names[current_value_index]
    
    clabel := strings.clone_to_cstring(label, context.temp_allocator)
    if BeginCombo(clabel, strings.unsafe_string_to_cstring(current_value_name), combo_flags) {
        for i in 0..<len(ti_enum.values) {
            if Selectable(strings.unsafe_string_to_cstring(ti_enum.names[i]), enum_value == ti_enum.values[i], selectable_flags, {}) {
                enum_value = ti_enum.values[i]
            }
        }
        EndCombo()
    }
  
    switch ti_base.size {
      case 1: ((^u8 )(value.data))^ = auto_cast enum_value
      case 2: ((^u16)(value.data))^ = auto_cast enum_value
      case 4: ((^u32)(value.data))^ = auto_cast enum_value
      case 8: ((^u64)(value.data))^ = auto_cast enum_value
    }
}

ComboUnion :: proc(
    label            : string, 
    value            : ^$T, 
    combo_flags      : ComboFlags = {}, 
    selectable_flags : SelectableFlags = {}
) {
    clabel := strings.clone_to_cstring(label, context.temp_allocator)
    values := reflect.enum_field_values(T)
    names  := reflect.enum_field_names(T)
    current_value_index := slice.linear_search(values, T(value^)) or_else 0 
    current_value_name  := names[current_value_index]
    
    if BeginCombo(clabel, strings.unsafe_string_to_cstring(current_value_name), combo_flags) {
        for i in 0..<len(values) {
            if SelectableEx(strings.unsafe_string_to_cstring(names[i]), value^ == T(values[i]), selectable_flags, {}) {
                value^ = T(values[i])
            }
        }
        EndCombo()
    }
}

InputDateTime :: proc(label: string, value: ^time.Time, help_text := "") {
    clabel := fmt.ctprintf("%v\n%v###%v", label, value^, label)
    if TreeNode(clabel) {
        if help_text != "" {
            SameLine()
            HelpMarker(help_text)
        }
        
        year, month, day     := time.date(value^)
        hour, minute, second := time.clock(value^)
        
        SetNextItemWidth(100)
        InputInt("###Day", transmute(^i32) &day)
        day = clamp(day, 1, 31)

        SameLine()
        SetNextItemWidth(100)
        ComboEnum("###Month", &month)

        SameLine()
        SetNextItemWidth(100) 
        InputInt("Date###Year", transmute(^i32) &year)
        year = clamp(year, 1970, 3000)

        SetNextItemWidth(100)
        InputInt("###Hour", transmute(^i32) &hour)
        hour = clamp(hour, 0, 23)

        SameLine()
        SetNextItemWidth(100)
        InputInt("###Minute", transmute(^i32) &minute)
        minute = clamp(minute, 0, 59)

        SameLine()
        SetNextItemWidth(100)
        InputInt("Time###Second", transmute(^i32) &second)
        second = clamp(second, 0, 59)

        result, ok := time.datetime_to_time(year, int(month), day, hour, minute, second)
        if !ok {
            TextUnformatted("Unable to parse date/time!")
        } else {
            value^ = result
        }
        TreePop()
    } 
    else if help_text != "" {
        SameLine()
        HelpMarker(help_text)
    }
}

TreeNodeAny :: proc(label: string, value: any, flags: TreeNodeFlags = {}, rclick_struct_callback: proc(any) = nil) {
    if value.data == nil do return
    
    // Special cases for some data types.
    // Maybe it would be nice to let users register their own callbacks to do special handling for their own data types.
    switch value.id {
      case typeid_of(time.Time):
        InputDateTime(label, auto_cast value.data)
        return
    }
    
    ti_base := runtime.type_info_base(type_info_of(value.id))
    
    // all variant cases will return on success
    // breaking from this block will do the generic case
    L_do_variant: {
        #partial switch ti_variant in ti_base.variant {
          case runtime.Type_Info_Struct:
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            if TreeNodeEx(clabel, flags) {
                for i in 0..<ti_variant.field_count {
                    type   := ti_variant.types  [i]
                    name   := ti_variant.names  [i]
                    offset := ti_variant.offsets[i]
                    member_any  := runtime.Raw_Any {
                        data = mem.ptr_offset(cast(^byte)value.data, offset),
                        id   = type.id,
                    }
                    TreeNodeAny(name, transmute(any) member_any, flags, rclick_struct_callback)
                }
                TreePop()
            }
            if IsItemClicked(.Right) && rclick_struct_callback != nil {
                rclick_struct_callback(value)
            }
            return
            
            
          case runtime.Type_Info_Array:
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            
            if ti_variant.elem.id == u8 {
                InputText(clabel, cstring(value.data), uint(ti_variant.count), {})
                return
            }
            
            // If this is an array of few scalar elements, we present it in a more compact manner using InputScalarN.
            #partial switch ti_elem_variant in runtime.type_info_base(ti_variant.elem).variant {
              case runtime.Type_Info_Integer, runtime.Type_Info_Float: 
                COMPACT_MODE_ELEMENT_COUNT :: 4
                data_type := DetermineDataType(ti_variant.elem)
                if data_type >= auto_cast 0 && ti_variant.count <= COMPACT_MODE_ELEMENT_COUNT {
                    InputScalarN(clabel, data_type, value.data, cast(i32) ti_variant.count)
                    return
                }
            }
            
            if TreeNodeEx(clabel, flags) {
                for i in 0..<ti_variant.count {
                    elem_any := runtime.Raw_Any {
                        data = mem.ptr_offset(cast(^byte)value.data, i * ti_variant.elem_size),
                        id   = ti_variant.elem.id,
                    }
                    TreeNodeAny(fmt.tprintf("%v", i), transmute(any) elem_any, flags, rclick_struct_callback)
                }
                TreePop()
            }
            
            if IsItemClicked(.Right) && rclick_struct_callback != nil {
                rclick_struct_callback(value)
            }
            return
            
            
          case runtime.Type_Info_Slice:
            raw_slice := (transmute(^runtime.Raw_Slice) value.data)^
            if raw_slice.data == nil {
                break L_do_variant
            }
            
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            
            if ti_variant.elem.id == u8 {
                cstr := cstring(raw_slice.data)
                InputText(clabel, cstr, cast(uint) raw_slice.len, {})
                return
            }
            
            if TreeNodeEx(clabel, flags) {
                for i in 0..<raw_slice.len {
                    elem_any := runtime.Raw_Any {
                        data = mem.ptr_offset(cast(^byte)raw_slice.data, i * ti_variant.elem_size),
                        id   = ti_variant.elem.id,
                    }
                    TreeNodeAny(fmt.tprintf("%v", i), transmute(any) elem_any, flags, rclick_struct_callback)
                }
                TreePop()
            }
            return
            
            
          case runtime.Type_Info_Fixed_Capacity_Dynamic_Array:
            data_ptr := value.data
            len_ptr  := cast(^int) mem.ptr_offset(cast(^byte) value.data, cast(int) ti_variant.len_offset)
            
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            
            if ti_variant.elem.id == u8 {
                cstr := cstring(data_ptr)
                if InputText(clabel, cstr, uint(ti_variant.capacity), {}) {
                    len_ptr^ = len(cstr)
                }
                return
            }
            
            if TreeNodeEx(clabel, flags) {
                // TODO: add logic to let user modify the current count, but keep it within valid bounds.
                if InputScalar("len", .S64, len_ptr) {
                    len_ptr^ = clamp(len_ptr^, 0, ti_variant.capacity)
                }
                
                for i in 0..<len_ptr^ {
                    elem_any := runtime.Raw_Any {
                        data = mem.ptr_offset(cast(^byte)data_ptr, i * ti_variant.elem_size),
                        id   = ti_variant.elem.id,
                    }
                    TreeNodeAny(fmt.tprintf("%v", i), transmute(any) elem_any, flags, rclick_struct_callback)
                }
                TreePop()
            }
            return
            
          case runtime.Type_Info_Dynamic_Array:
            raw_dynamic_array := (transmute(^runtime.Raw_Dynamic_Array) value.data)^
            
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            
            // Special case for text input when element type is u8.
            if ti_variant.elem.id == u8 {
                char_array_ptr := transmute(^[dynamic]u8) (value.data)
                
                // If array data is nil, and we have no allocator proc set, then we don't presume to use the current context allocator.
                // The user will need to at least set the allocator manually before the dynamic array can be used for text input.
                // Ideally, the user should manually allocate the array with a sensible initial size.
                if raw_dynamic_array.data == nil {
                    if raw_dynamic_array.allocator.procedure == nil {
                        BulletText(fmt.ctprintf("%v: ([dynamic]u8 with no allocator set)", label))
                        return
                    }
                    
                    // Maybe we will decide we don't want to do this later on...
                    DEFAULT_INITIAL_ARRAY_SIZE :: 8
                    reserve(char_array_ptr, DEFAULT_INITIAL_ARRAY_SIZE)
                }
                
                InputTextDynamic(clabel, char_array_ptr)
                return
            }
            
            if raw_dynamic_array.data == nil && raw_dynamic_array.allocator.procedure == nil {
                break L_do_variant
            }
            
            // TODO: add controls to add/remove elements from dynamic array
            
            if TreeNodeEx(clabel, flags) {
                for i in 0..<raw_dynamic_array.len {
                    elem_any := runtime.Raw_Any {
                        data = mem.ptr_offset(cast(^byte)raw_dynamic_array.data, i * ti_variant.elem_size),
                        id   = ti_variant.elem.id,
                    }
                    TreeNodeAny(fmt.tprintf("%v", i), transmute(any) elem_any, flags, rclick_struct_callback)
                }
                TreePop()
            }
            return
            
          case runtime.Type_Info_Enum:
            ComboEnumDynamic(label, value)
            return
            
          case runtime.Type_Info_Integer:
            data_type := DetermineDataType(ti_base)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti_base.size)
            }
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            InputScalar(clabel, data_type, value.data)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti_base.size)
            }
            return
            
          case runtime.Type_Info_Float:
            data_type := DetermineDataType(ti_base)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti_base.size)
            }
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            InputScalar(clabel, data_type, value.data)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti_base.size)
            }
            return
            
          case runtime.Type_Info_Boolean:
            bool_ptr := cast(^bool) value.data
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            if RadioButton(clabel, bool_ptr^) { 
                bool_ptr^ = !bool_ptr^
            }
            return
            
          case runtime.Type_Info_Bit_Set:
            set: bit_set[0..<128]
            mem.copy(&set, value.data, ti_base.size);
            
            clabel := strings.clone_to_cstring(label, context.temp_allocator)
            if TreeNodeEx(clabel, flags) {
                #partial switch elem_tiv in runtime.type_info_base(ti_variant.elem).variant {
                  case runtime.Type_Info_Integer:
                    for i in ti_variant.lower..=ti_variant.upper {
                        cname := fmt.ctprint(i)
                        bit_position := cast(int) (i - ti_variant.lower)
                        if RadioButton(cname, bit_position in set) { 
                            set ~= { bit_position }
                        }
                    }
                    
                  case runtime.Type_Info_Rune:
                    for i in ti_variant.lower..=ti_variant.upper {
                        cname := fmt.ctprint(rune(i))
                        bit_position := cast(int) (i - ti_variant.lower)
                        if RadioButton(cname, bit_position in set) { 
                            set ~= { bit_position }
                        }
                    }
                    
                  case runtime.Type_Info_Enum:
                    L_enum_case: {
                        lower := slice.linear_search(elem_tiv.values, auto_cast ti_variant.lower) or_break L_enum_case
                        upper := slice.linear_search(elem_tiv.values, auto_cast ti_variant.upper) or_break L_enum_case
                        for i in lower..=upper {
                            cname := strings.unsafe_string_to_cstring(elem_tiv.names[i])
                            bit_position := cast(int) elem_tiv.values[i]
                            if RadioButton(cname, bit_position in set) { 
                                set ~= { bit_position }
                            }
                        }
                    }
                }
                TreePop()
            }
            
            mem.copy(value.data, &set, ti_base.size);
            return
            
            
          case runtime.Type_Info_String:
            BulletText(fmt.ctprintf("%v: \"%v\"", label, value))
            return
        }
    }
    
    // Generic case simply displays value with default formatting.
    BulletText(fmt.ctprintf("%v: %v", label, value))
    return
}

// NOTE: We return -1 in the case that there is no valid mapping.
DetermineDataType :: proc(type_info: ^runtime.Type_Info) -> DataType {
    ti_base := runtime.type_info_base(type_info)
    
    #partial switch ti_variant in ti_base.variant {
      case runtime.Type_Info_Integer:   
        // TODO: Currently ignoring endianness. Not sure what to do about that for now. We would probably need to have handling in caller for this...
        switch ti_base.size {
          case 1: return .S8  if ti_variant.signed else .U8 
          case 2: return .S16 if ti_variant.signed else .U16
          case 4: return .S32 if ti_variant.signed else .U32
          case 8: return .S64 if ti_variant.signed else .U64
        }
        
      case runtime.Type_Info_Float:
        switch ti_base.size {
          case 4: return .Float
          case 8: return .Double
        }
        
      case runtime.Type_Info_Boolean:
        return .Bool
    }
    
    return cast(DataType) -1;
}



@(private)
reverse_bytes_in_place :: proc(data: rawptr, len: int) {
    start := cast(uintptr) data;
    end   := start + (cast(uintptr) len) - 1
    
    for start <= end {
        temp                := (cast(^byte)start)^
        (cast(^byte)start)^  = (cast(^byte)end  )^
        (cast(^byte)end  )^  = temp
        
        start += 1
        end   -= 1
    }
}
