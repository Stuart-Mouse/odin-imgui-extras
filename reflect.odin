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
    label := strings.clone_to_cstring(label, context.temp_allocator)
    
    selected_key_string := cstring(raw_data(fmt.tprintf("%v\x00", selected)))
    if BeginCombo(label, selected_key_string, combo_flags) {
        for k in _map {
            key_string := cstring(raw_data(fmt.tprintf("%v\x00", k)))
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
    label  := strings.clone_to_cstring(label, context.temp_allocator)
    values := reflect.enum_field_values(T)
    names  := reflect.enum_field_names(T)
    current_value_index := slice.linear_search(values, auto_cast value^) or_else 0 // Could we use binary search? need to find out if values are always ordered...
    current_value_name  := names[current_value_index]
    if BeginCombo(label, cstring(raw_data(current_value_name)), combo_flags) {
        for i in 0..<len(values) {
            if Selectable(cstring(raw_data(names[i])), value^ == T(values[i]), selectable_flags, {}) {
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
      label := strings.clone_to_cstring(label, context.temp_allocator)
  
    ti := type_info_of(value.id)
    if ti_named, ok := ti.variant.(runtime.Type_Info_Named); ok {
          ti = ti_named.base
    }
    ti_variant, ok := ti.variant.(runtime.Type_Info_Enum)
    if !ok do return
  
    enum_value : runtime.Type_Info_Enum_Value
    switch ti.size {
      case 1: enum_value = auto_cast ((^u8 )(value.data))^
      case 2: enum_value = auto_cast ((^u16)(value.data))^
      case 4: enum_value = auto_cast ((^u32)(value.data))^
      case 8: enum_value = auto_cast ((^u64)(value.data))^
    }
  
    current_value_index := slice.linear_search(ti_variant.values, enum_value) or_else 0 
    current_value_name  := ti_variant.names[current_value_index]
    
    if BeginCombo(label, cstring(raw_data(current_value_name)), combo_flags) {
        for i in 0..<len(ti_variant.values) {
            if Selectable(cstring(raw_data(ti_variant.names[i])), enum_value == ti_variant.values[i], selectable_flags, {}) {
                enum_value = ti_variant.values[i]
            }
        }
        EndCombo()
    }
  
    switch ti.size {
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
    label  := strings.clone_to_cstring(label, context.temp_allocator)
    values := reflect.enum_field_values(T)
    names  := reflect.enum_field_names(T)
    current_value_index := slice.linear_search(values, T(value^)) or_else 0 
    current_value_name  := names[current_value_index]
    if BeginCombo(label, cstring(raw_data(current_value_name)), combo_flags) {
        for i in 0..<len(values) {
            if SelectableEx(cstring(raw_data(names[i])), value^ == T(values[i]), selectable_flags, {}) {
            value^ = T(values[i])
            }
        }
        EndCombo()
    }
}

InputDateTime :: proc(label: string, value: ^time.Time, help_text := "") {
    label := fmt.tprintf("%v\n%v###%v\x00", label, value^, label)
    
    if TreeNode(cstring(raw_data(label))) {
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

// TODO: add support for fixed-capacity resizable arrays, add support for editting string-like arrays as text
TreeNodeAny :: proc(label: string, value: any, flags: TreeNodeFlags = {}, rclick_struct_callback: proc(any) = nil) {
    clabel := strings.clone_to_cstring(label, context.temp_allocator)

    if value.data == nil do return
    
    switch value.id {
      case typeid_of(time.Time):
        InputDateTime(label, auto_cast value.data)
        return
    }

    ti := runtime.type_info_base(type_info_of(value.id))
    // if ti_named, ok := ti.variant.(Type_Info_Named); ok {
    //     ti = ti_named.base
    // }
  
    // all variant cases will return on success
    // breaking from this block will do the generic case
    DoVariant: {
        #partial switch ti_variant in ti.variant {
          case runtime.Type_Info_Struct:
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
            // if ti_variant.elem.id == u8 {
            //     InputText(label, cstring(value.data), uint(ti_variant.count), {})
            //     return
            // }
            
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
                break DoVariant
            }
            // if ti_variant.elem.id == u8 {
            //     InputText(clabel, cstring(raw_slice.data), uint(raw_slice.len), {})
            //     return
            // }
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
            
            if ti_variant.elem.id == u8 {
                c_str := cstring(data_ptr)
                if InputText(clabel, c_str, uint(ti_variant.capacity), {}) {
                    len_ptr^ = len(c_str)
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
            if raw_dynamic_array.data == nil {
                break DoVariant
            }
            // if ti_variant.elem.id == u8 {
            //     InputTextDynamic(label, transmute(^[dynamic]u8)(value.data))
            //     return
            // }
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
            data_type := DetermineDataType(ti)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti.size)
            }
            InputScalar(clabel, data_type, value.data)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti.size)
            }
            return
            
          case runtime.Type_Info_Float:
            data_type := DetermineDataType(ti)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti.size)
            }
            InputScalar(clabel, data_type, value.data)
            if ti_variant.endianness == .Big {
                reverse_bytes_in_place(value.data, ti.size)
            }
            return
            
          case runtime.Type_Info_Boolean:
            bool_ptr := cast(^bool) value.data
            if (RadioButton(clabel, bool_ptr^)) { 
                bool_ptr^ = !bool_ptr^
            }
            return
            
          case runtime.Type_Info_Bit_Set:
            set: bit_set[0..<128]
            mem.copy(&set, value.data, ti.size);
            
            if TreeNodeEx(clabel, flags) {
                #partial switch elem_tiv in runtime.type_info_base(ti_variant.elem).variant {
                    case runtime.Type_Info_Integer:
                        for i in ti_variant.lower..=ti_variant.upper {
                            if (RadioButton(cstring(raw_data(fmt.tprint(i))), int(i - ti_variant.lower) in set)) { 
                                set ~= { int(i - ti_variant.lower) }
                            }
                        }
                    case runtime.Type_Info_Rune:
                        for i in ti_variant.lower..=ti_variant.upper {
                            if (RadioButton(cstring(raw_data(fmt.tprint(rune(i)))), int(i - ti_variant.lower) in set)) { 
                                set ~= { int(i - ti_variant.lower) }
                            }
                        }
                    case runtime.Type_Info_Enum:
                        lower := slice.linear_search(elem_tiv.values, auto_cast ti_variant.lower) or_else 0
                        upper := slice.linear_search(elem_tiv.values, auto_cast ti_variant.upper) or_else 0
                        for i in lower..=upper {
                            if (RadioButton(cstring(raw_data(elem_tiv.names[i])), int(elem_tiv.values[i]) in set)) { 
                                set ~= { int(elem_tiv.values[i]) }
                            }
                        }
                }
                TreePop()
            }
            
            mem.copy(value.data, &set, ti.size);
            return
            
            
          case runtime.Type_Info_String:
            BulletText(cstring(raw_data(fmt.tprintf("%v: \"%v\"", label, value))))
            return
        }
    }

    // generic case simply displays value with default formatting
    BulletText(cstring(raw_data(fmt.tprintf("%v: %v", label, value))))
    return

    // TODO: may be able to create a dynamic_float_cast proc similar to the integer equivalent
    get_f32_value :: proc(value: any) -> (f32, bool) {
        f32_value : f32
        if value.data == nil do return 0, false
      
        ti := runtime.type_info_base(type_info_of(value.id))
        ti_variant := ti.variant.(runtime.Type_Info_Float)

        switch ti.size {
            case 2: f32_value = auto_cast ((^f16)(value.data))^
            case 4: f32_value = auto_cast ((^f32)(value.data))^
            case 8: f32_value = auto_cast ((^f64)(value.data))^
        }

        return f32_value, true
    }

    set_f32_value :: proc(value: any, f32_value: f32) -> bool {
        if value.data == nil do return false
        
        ti := runtime.type_info_base(type_info_of(value.id))
        ti_variant := ti.variant.(runtime.Type_Info_Float)

        switch ti.size {
            case 2: ((^f16)(value.data))^ = auto_cast f32_value
            case 4: ((^f32)(value.data))^ = auto_cast f32_value
            case 8: ((^f64)(value.data))^ = auto_cast f32_value
        }

        return true
    }
}

// BeginMaybe :: proc(enabled: bool, hide_disabled: bool) -> bool {
//     if Checkbox("##", &enabled) {
//         enabled = !enabled
//     }

//     if !enabled && hide_disabled {
//         return false
//     }
    
//     BeginDisabled(!enabled)
//     return true
// }

// EndMaybe :: proc(disabled: bool) {
//     EndDisabled()
// }

@(private)
dynamic_float_cast :: proc(dst, src: any, enforce_size := false) -> bool {
    ti_src := runtime.type_info_base(type_info_of(src.id))
    ti_dst := runtime.type_info_base(type_info_of(dst.id))
  
    if enforce_size && ti_src.size > ti_dst.size {
        return false
    }
  
    _, allow_src := ti_src.variant.(runtime.Type_Info_Float)
    _, allow_dst := ti_dst.variant.(runtime.Type_Info_Float)
    if !allow_src || !allow_dst {
        return false
    }
  
    f64_value: f64
  
    switch ti_src.size {
        case 2: f64_value = auto_cast (cast(^f16)src.data)^
        case 4: f64_value = auto_cast (cast(^f32)src.data)^
        case 8: f64_value = auto_cast (cast(^f64)src.data)^
    }
  
    switch ti_dst.size {
        case 2: (cast(^f16)dst.data)^ = auto_cast f64_value
        case 4: (cast(^f32)dst.data)^ = auto_cast f64_value
        case 8: (cast(^f64)dst.data)^ = auto_cast f64_value
    }
  
    return true
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
    end   := start + cast(uintptr) len - 1
    
    for start <= end {
        temp := (cast(^byte)start)^
        (cast(^byte)start)^ = (cast(^byte)end)^
        (cast(^byte)end)^ = temp
        
        start += 1
        end   -= 1
    }
}