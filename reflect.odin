package imgui_ext

InputTextDynamicCallbackUserData :: struct {
    buf                   : ^[dynamic] u8,
    ChainCallback         : InputTextCallback,
    ChainCallbackUserData : rawptr,
}

InputTextDynamicCallback : InputTextCallback : proc "c" (data: ^InputTextCallbackData) -> c.int {
    context = runtime.default_context()
	user_data := cast(^InputTextDynamicCallbackUserData) data.UserData
    if .CallbackResize in data.EventFlag {
		new_len := int(data.BufTextLen)
        new_cap := max(2, cap(user_data.buf), math.next_power_of_two(new_len))
		reserve(user_data.buf, new_cap)
		resize(user_data.buf, new_len)
		data.Buf = cstring(raw_data(user_data.buf^))
		return 0
    }
	if user_data.ChainCallback != nil {
		data.UserData = user_data.ChainCallbackUserData
		return user_data.ChainCallback(data)
	}
    return 0
}

InputTextDynamic :: proc(label: cstring, buf: ^[dynamic]u8, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool {
	cb_user_data : InputTextDynamicCallbackUserData = {
		buf 				  = buf,
		ChainCallback 		  = callback,
		ChainCallbackUserData = user_data,
	}
	return InputTextEx(label, cstring(raw_data(buf^)), cap(buf^), flags | { .CallbackResize }, InputTextDynamicCallback, &cb_user_data)
}

InputTextWithHintDynamic :: proc(label, hint: cstring, buf: ^[dynamic]u8, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool {
	cb_user_data : InputTextDynamicCallbackUserData = {
		buf 				  = buf,
		ChainCallback 		  = callback,
		ChainCallbackUserData = user_data,
	}
	return InputTextWithHintEx(label, hint, cstring(raw_data(buf^)), cap(buf^), flags | { .CallbackResize }, InputTextDynamicCallback, &cb_user_data)
}

InputTextMultilineDynamic :: proc(label: cstring, buf: ^[dynamic]u8, size: Vec2 = {}, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool {
	cb_user_data : InputTextDynamicCallbackUserData = {
		buf 				  = buf,
		ChainCallback 		  = callback,
		ChainCallbackUserData = user_data,
	}
	return InputTextMultilineEx(label, cstring(raw_data(buf^)), cap(buf^), size, flags | { .CallbackResize }, InputTextDynamicCallback, &cb_user_data)
}

TextUnformattedString :: proc(text: string) {
	str := raw_data(text)
	TextUnformattedEx(cstring(&str[0]), cstring(&str[len(text)]))
}

ComboEnum :: proc(label: cstring, value: ^$T, combo_flags: ComboFlags = {}, selectable_flags: SelectableFlags = {}) {
	values 				:= reflect.enum_field_values(T)
	names  				:= reflect.enum_field_names(T)
	current_value_index := slice.linear_search(values, auto_cast value^) or_else 0 // Could we use binary search? need to find out if values are always ordered...
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

// If the given type is not an enum, the procedure will do nothing and return
ComboEnumDynamic :: proc(
	label            : cstring, 
	value            : any, 
	combo_flags      : ComboFlags = {}, 
	selectable_flags : SelectableFlags = {}
  ) {
	ti := type_info_of(value.id)
	if ti_named, ok := ti.variant.(runtime.Type_Info_Named); ok {
	  	ti = ti_named.base
	}
	tiv, ok := ti.variant.(runtime.Type_Info_Enum)
	if !ok do return
  
	enum_value : runtime.Type_Info_Enum_Value
	switch ti.size {
		case 1: enum_value = auto_cast ((^u8 )(value.data))^
		case 2: enum_value = auto_cast ((^u16)(value.data))^
		case 4: enum_value = auto_cast ((^u32)(value.data))^
		case 8: enum_value = auto_cast ((^u64)(value.data))^
	}
  
	current_value_index := slice.linear_search(tiv.values, enum_value) or_else 0 
	current_value_name  := tiv.names[current_value_index]
	if BeginCombo(label, cstring(raw_data(current_value_name)), combo_flags) {
		for i in 0..<len(tiv.values) {
			if SelectableEx(cstring(raw_data(tiv.names[i])), enum_value == tiv.values[i], selectable_flags, {}) {
				enum_value = tiv.values[i]
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
	label            : cstring, 
	value            : ^$T, 
	combo_flags      : ComboFlags = {}, 
	selectable_flags : SelectableFlags = {}
) {
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

InputDateTime :: proc(label: cstring, value: ^time.Time, help_text := "") {
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

TreeNodeAny :: proc(label: cstring, value: any, flags: TreeNodeFlags = {}, rclick_struct_callback: proc(any) = nil) {
	using runtime
	value_data, value_id := reflect.any_data(value)
	if value_data == nil do return
  
	switch value_id {
		case typeid_of(time.Time):
			InputDateTime(label, auto_cast value_data)
			return
	}

	ti := type_info_of(value_id)
	if ti_named, ok := ti.variant.(Type_Info_Named); ok {
		ti = ti_named.base
	}
  
	// all variant cases will return on success
	// breaking from this block will do the generic case
	DoVariant: {
		#partial switch tiv in ti.variant {
			case Type_Info_Struct:
				if TreeNodeEx(label, flags) {
					member_count := len(tiv.names)
					for i in 0..<member_count {
							type   := tiv.types  [i]
							name   := tiv.names  [i]
							offset := tiv.offsets[i]
							member_any  := Raw_Any {
							data = mem.ptr_offset(cast(^byte)value_data, offset),
							id   = type.id,
						}
						TreeNodeAny(cstring(raw_data(name)), transmute(any) member_any, flags, rclick_struct_callback)
					}
					TreePop()
				}
				if IsItemClickedEx(.Right) && rclick_struct_callback != nil {
					rclick_struct_callback(value)
				}
				return
	
			case Type_Info_Array:
				// if tiv.elem.id == u8 {
				// 	InputText(label, cstring(value_data), uint(tiv.count), {})
				// 	return
				// }
				#partial switch tie in type_info_base(tiv.elem).variant {
					case Type_Info_Integer: 
						switch tiv.count {
							case 1:
								elem_any := transmute(any) runtime.Raw_Any {
									data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id,
								}
								value : i32
								dynamic_int_cast(value, elem_any)
								InputInt(label, &value)
								dynamic_int_cast(elem_any, value)
								return
							case 2:
								elem_any := transmute([2]any) [2]runtime.Raw_Any {
									{ data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id }, 
									{ data = mem.ptr_offset(cast(^byte)value_data, 1 * tiv.elem_size), id = tiv.elem.id },
								}
								values : [2] i32 
								dynamic_int_cast(values[0], elem_any[0])
								dynamic_int_cast(values[1], elem_any[1])
								InputInt2(label, &values, {})
								dynamic_int_cast(elem_any[0], values[0])
								dynamic_int_cast(elem_any[1], values[1])
								return
							case 3:
								elem_any := transmute([3]any) [3]runtime.Raw_Any {
									{ data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id }, 
									{ data = mem.ptr_offset(cast(^byte)value_data, 1 * tiv.elem_size), id = tiv.elem.id },
									{ data = mem.ptr_offset(cast(^byte)value_data, 2 * tiv.elem_size), id = tiv.elem.id },
								}
								values : [3] i32 
								dynamic_int_cast(values[0], elem_any[0])
								dynamic_int_cast(values[1], elem_any[1])
								dynamic_int_cast(values[2], elem_any[2])
								InputInt3(label, &values, {})
								dynamic_int_cast(elem_any[0], values[0])
								dynamic_int_cast(elem_any[1], values[1])
								dynamic_int_cast(elem_any[2], values[2])
								return
							case 4:
								elem_any := transmute([4]any) [4]runtime.Raw_Any {
									{ data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id }, 
									{ data = mem.ptr_offset(cast(^byte)value_data, 1 * tiv.elem_size), id = tiv.elem.id },
									{ data = mem.ptr_offset(cast(^byte)value_data, 2 * tiv.elem_size), id = tiv.elem.id },
									{ data = mem.ptr_offset(cast(^byte)value_data, 3 * tiv.elem_size), id = tiv.elem.id },
								}
								values : [4] i32 
								dynamic_int_cast(values[0], elem_any[0])
								dynamic_int_cast(values[1], elem_any[1])
								dynamic_int_cast(values[2], elem_any[2])
								dynamic_int_cast(values[3], elem_any[3])
								InputInt4(label, &values, {})
								dynamic_int_cast(elem_any[0], values[0])
								dynamic_int_cast(elem_any[1], values[1])
								dynamic_int_cast(elem_any[2], values[2])
								dynamic_int_cast(elem_any[3], values[3])
								return
						}
					
					case Type_Info_Float: 
						switch tiv.count {
							case 1:
								elem_any := transmute(any) runtime.Raw_Any {
									data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id,
								}
								f32_value, ok := get_f32_value(elem_any)
								if !ok do break DoVariant
								InputFloat(label, &f32_value)
								set_f32_value(elem_any, f32_value)
								return
							case 2:
								elem_any := transmute([2]any) [2]runtime.Raw_Any {
									{ data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id }, 
									{ data = mem.ptr_offset(cast(^byte)value_data, 1 * tiv.elem_size), id = tiv.elem.id },
								}
								values : [2] f32 
								ok : bool
								values[0], ok = get_f32_value(elem_any[0])
								values[1], ok = get_f32_value(elem_any[1])
								if !ok do break DoVariant
								InputFloat2(label, &values)
								set_f32_value(elem_any[0], values[0])
								set_f32_value(elem_any[1], values[1])
								return
							case 3:
								elem_any := transmute([3]any) [3]runtime.Raw_Any {
									{ data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id }, 
									{ data = mem.ptr_offset(cast(^byte)value_data, 1 * tiv.elem_size), id = tiv.elem.id },
									{ data = mem.ptr_offset(cast(^byte)value_data, 2 * tiv.elem_size), id = tiv.elem.id },
								}
								values : [3] f32 
								ok : bool
								values[0], ok = get_f32_value(elem_any[0])
								values[1], ok = get_f32_value(elem_any[1])
								values[2], ok = get_f32_value(elem_any[2])
								if !ok do break DoVariant
								InputFloat3(label, &values)
								set_f32_value(elem_any[0], values[0])
								set_f32_value(elem_any[1], values[1])
								set_f32_value(elem_any[2], values[2])
								return
							case 4:
								elem_any := transmute([4]any) [4]runtime.Raw_Any {
									{ data = mem.ptr_offset(cast(^byte)value_data, 0 * tiv.elem_size), id = tiv.elem.id }, 
									{ data = mem.ptr_offset(cast(^byte)value_data, 1 * tiv.elem_size), id = tiv.elem.id },
									{ data = mem.ptr_offset(cast(^byte)value_data, 2 * tiv.elem_size), id = tiv.elem.id },
									{ data = mem.ptr_offset(cast(^byte)value_data, 3 * tiv.elem_size), id = tiv.elem.id },
								}
								values : [4] f32 
								ok : bool
								values[0], ok = get_f32_value(elem_any[0])
								values[1], ok = get_f32_value(elem_any[1])
								values[2], ok = get_f32_value(elem_any[2])
								values[3], ok = get_f32_value(elem_any[3])
								if !ok do break DoVariant
								InputFloat4(label, &values)
								set_f32_value(elem_any[0], values[0])
								set_f32_value(elem_any[1], values[1])
								set_f32_value(elem_any[2], values[2])
								set_f32_value(elem_any[3], values[3])
								return
						}
				}
				if TreeNodeEx(label, flags) {
					for i in 0..<tiv.count {
						elem_any := runtime.Raw_Any {
							data = mem.ptr_offset(cast(^byte)value_data, i * tiv.elem_size),
							id   = tiv.elem.id,
						}
						TreeNodeAny(cstring(raw_data(fmt.tprintf("%v", i))), transmute(any) elem_any, flags, rclick_struct_callback)
					}
					TreePop()
				}
				if IsItemClickedEx(.Right) && rclick_struct_callback != nil {
					rclick_struct_callback(value)
				}
				return
	
			case Type_Info_Slice:
				raw_slice := (transmute(^Raw_Slice) value.data)^
				if raw_slice.data == nil {
					break DoVariant
				}
				// if tiv.elem.id == u8 {
				// 	InputText(label, cstring(raw_slice.data), uint(raw_slice.len), {})
				// 	return
				// }
				if TreeNodeEx(label, flags) {
					for i in 0..<raw_slice.len {
						elem_any := runtime.Raw_Any {
							data = mem.ptr_offset(cast(^byte)value_data, i * tiv.elem_size),
							id   = tiv.elem.id,
						}
						TreeNodeAny(cstring(raw_data(fmt.tprintf("%v", i))), transmute(any) elem_any, flags, rclick_struct_callback)
					}
					TreePop()
				}
				return
	
			case Type_Info_Dynamic_Array:
				raw_dynamic_array := (transmute(^Raw_Dynamic_Array) value.data)^
				if raw_dynamic_array.data == nil {
					break DoVariant
				}
				// if tiv.elem.id == u8 {
				// 	InputTextDynamic(label, transmute(^[dynamic]u8)(value.data))
				// 	return
				// }
				if TreeNodeEx(label, flags) {
					for i in 0..<raw_dynamic_array.len {
						elem_any := runtime.Raw_Any {
							data = mem.ptr_offset(cast(^byte)raw_dynamic_array.data, i * tiv.elem_size),
							id   = tiv.elem.id,
						}
						TreeNodeAny(cstring(raw_data(fmt.tprintf("%v", i))), transmute(any) elem_any, flags, rclick_struct_callback)
					}
					TreePop()
				}
				return
	
			case Type_Info_Enum:
				ComboEnumDynamic(label, value)
				return
	
			case Type_Info_Integer:
				i32_value : i32
				dynamic_int_cast(i32_value, value)
				InputInt(label, &i32_value)
				dynamic_int_cast(value, i32_value)
				return
	
			case Type_Info_Float: 
				f32_value, ok := get_f32_value(value)
				if !ok do break DoVariant
				InputFloat(label, &f32_value)
				set_f32_value(value, f32_value)
				return
	
			case Type_Info_Boolean:
				bool_value : bool
				if !dynamic_int_cast(bool_value, value) do break DoVariant
				if (RadioButton(label, bool_value)) { 
					bool_value = !bool_value 
				} 
				dynamic_int_cast(value, bool_value)
				return
	
			case Type_Info_Bit_Set:
				set : bit_set[0..<128]
				dynamic_int_cast(set, value)
				if TreeNodeEx(label, flags) {
					#partial switch elem_tiv in type_info_base(tiv.elem).variant {
						case Type_Info_Integer:
							for i in tiv.lower..=tiv.upper {
								if (RadioButton(cstring(raw_data(fmt.tprint(i))), int(i - tiv.lower) in set)) { 
									set ~= { int(i - tiv.lower) }
								}
							}
						case Type_Info_Rune:
							for i in tiv.lower..=tiv.upper {
								if (RadioButton(cstring(raw_data(fmt.tprint(rune(i)))), int(i - tiv.lower) in set)) { 
									set ~= { int(i - tiv.lower) }
								}
							}
						case Type_Info_Enum:
							lower := slice.linear_search(elem_tiv.values, auto_cast tiv.lower) or_else 0
							upper := slice.linear_search(elem_tiv.values, auto_cast tiv.upper) or_else 0
							for i in lower..=upper {
								if (RadioButton(cstring(raw_data(elem_tiv.names[i])), int(elem_tiv.values[i]) in set)) { 
									set ~= { int(elem_tiv.values[i]) }
								}
							}
					}
					TreePop()
				}
				dynamic_int_cast(value, set)
				return

		
			case Type_Info_String:
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
		value_data, value_id := reflect.any_data(value)
		if value_data == nil do return 0, false
	  
		ti := type_info_base(type_info_of(value_id))
		tiv := ti.variant.(Type_Info_Float)

		switch ti.size {
			case 2: f32_value = auto_cast ((^f16)(value.data))^
			case 4: f32_value = auto_cast ((^f32)(value.data))^
			case 8: f32_value = auto_cast ((^f64)(value.data))^
		}

		return f32_value, true
	}

	set_f32_value :: proc(value: any, f32_value: f32) -> bool {
		value_data, value_id := reflect.any_data(value)
		if value_data == nil do return false
		
		ti := type_info_base(type_info_of(value_id))
		tiv := ti.variant.(Type_Info_Float)

		switch ti.size {
			case 2: ((^f16)(value.data))^ = auto_cast f32_value
			case 4: ((^f32)(value.data))^ = auto_cast f32_value
			case 8: ((^f64)(value.data))^ = auto_cast f32_value
		}

		return true
	}
}

// BeginMaybe :: proc(enabled: bool, hide_disabled: bool) -> bool {
// 	if Checkbox("##", &enabled) {
// 		enabled = !enabled
// 	}

// 	if !enabled && hide_disabled {
// 		return false
// 	}
	
// 	BeginDisabled(!enabled)
// 	return true
// }

// EndMaybe :: proc(disabled: bool) {
// 	EndDisabled()
// }

@(private)
dynamic_int_cast :: proc(dst, src: any, enforce_size := false) -> bool {
	using runtime
	src := transmute(Raw_Any) src
	dst := transmute(Raw_Any) dst

	ti_src := type_info_base(type_info_of(src.id))
	ti_dst := type_info_base(type_info_of(dst.id))

	if enforce_size && ti_src.size > ti_dst.size {
		return false
	}

	for ti in ([]^Type_Info { ti_src, ti_dst }) {
		#partial switch ti_var in ti.variant {
			case Type_Info_Enum:
			case Type_Info_Bit_Set:
			case Type_Info_Integer:
			case Type_Info_Boolean:
			case: return false
		}
	}

	mem.copy(dst.data, src.data, min(ti_dst.size, ti_src.size))
	return true
}

HelpMarker :: proc(desc: string) {
	TextDisabled("(?)")
	if BeginItemTooltip() {
		PushTextWrapPos(GetFontSize() * 35)
		TextUnformattedString(desc)
		PopTextWrapPos()
		EndTooltip()
	}
}

import "core:math"
import "core:time"
import "core:slice"
import "core:reflect"
import "core:runtime"
import "core:mem"
import "core:fmt"
import "core:strings"
