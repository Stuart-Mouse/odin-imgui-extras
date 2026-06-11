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

InputTextDynamicCallbackUserData :: struct {
    buf:                 	^[dynamic] u8,
    ChainCallback:         	InputTextCallback,
    ChainCallbackUserData: 	rawptr,
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
        buf                   = buf,
        ChainCallback           = callback,
        ChainCallbackUserData = user_data,
    }
    return InputText(label, cstring(raw_data(buf^)), cap(buf^), flags | { .CallbackResize }, InputTextDynamicCallback, &cb_user_data)
}

InputTextWithHintDynamic :: proc(label, hint: cstring, buf: ^[dynamic]u8, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool {
    cb_user_data : InputTextDynamicCallbackUserData = {
        buf                   = buf,
        ChainCallback           = callback,
        ChainCallbackUserData = user_data,
    }
    return InputTextWithHint(label, hint, cstring(raw_data(buf^)), cap(buf^), flags | { .CallbackResize }, InputTextDynamicCallback, &cb_user_data)
}

InputTextMultilineDynamic :: proc(label: cstring, buf: ^[dynamic]u8, size: Vec2 = {}, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool {
    cb_user_data : InputTextDynamicCallbackUserData = {
        buf                   = buf,
        ChainCallback           = callback,
        ChainCallbackUserData = user_data,
    }
    return InputTextMultiline(label, cstring(raw_data(buf^)), cap(buf^), size, flags | { .CallbackResize }, InputTextDynamicCallback, &cb_user_data)
}

TextUnformattedString :: proc(text: string) {
    str := raw_data(text)
    TextUnformatted(cstring(&str[0]), cstring(&str[len(text)]))
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
