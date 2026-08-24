const r4os = @import("r4os");

const k = struct {
    fn puts(_: []const u8) void {}
    fn putDec(_: anytype) void {}
    fn putHex(_: anytype, _: u8) void {}
    fn putc(_: u8) void {}
};

const protocol_api = struct {
    const ProtocolBuffer = r4os.abi.ProtocolBuffer;
};

const r4p = struct {
    const DispatchFn = *const fn ([*:0]const u8, u32, *const protocol_api.ProtocolBuffer, *protocol_api.ProtocolBuffer) callconv(.c) i32;
    var dispatch_fn: ?DispatchFn = null;
    var active: bool = false;

    fn requiredSourceName(_: []const u8) []const u8 {
        return if (active) "r4p" else "none";
    }

    fn hasActiveR4p(_: []const u8) bool {
        return dispatch_fn != null;
    }

    fn dispatch(_: []const u8, op: u32, in_buffer: *const protocol_api.ProtocolBuffer, out_buffer: *protocol_api.ProtocolBuffer) i32 {
        const callback = dispatch_fn orelse return r4p_contract.AUDIO_SID_RESULT_UNSUPPORTED;
        const result = callback("audio.sid", op, in_buffer, out_buffer);
        if (result != -5) active = true;
        return result;
    }
};

const r4p_contract = struct {
    const AUDIO_SID_OP_CONFIGURE_MODEL = r4os.abi.audio_sid_op_configure_model;
    const AUDIO_SID_OP_WRITE_REGISTER = r4os.abi.audio_sid_op_write_register;
    const AUDIO_SID_OP_RESOLVE_IO = r4os.abi.audio_sid_op_resolve_io;
    const AUDIO_SID_RESULT_OK = r4os.abi.audio_sid_result_ok;
    const AUDIO_SID_RESULT_BAD_MODEL = r4os.abi.audio_sid_result_bad_model;
    const AUDIO_SID_RESULT_BAD_REGISTER = r4os.abi.audio_sid_result_bad_register;
    const AUDIO_SID_RESULT_BAD_ADDRESS = r4os.abi.audio_sid_result_bad_address;
    const AUDIO_SID_RESULT_UNSUPPORTED = r4os.abi.audio_sid_result_unsupported;
    const AUDIO_SID_MODEL_8580 = r4os.abi.audio_sid_model_8580;
    const AUDIO_SID_MODEL_6581 = r4os.abi.audio_sid_model_6581;
    const AUDIO_SID_REGISTER_OTHER = r4os.abi.audio_sid_register_other;
    const AUDIO_SID_REGISTER_VOICE = r4os.abi.audio_sid_register_voice;
    const AUDIO_SID_REGISTER_FILTER = r4os.abi.audio_sid_register_filter;
    const AUDIO_SID_REGISTER_VOLUME = r4os.abi.audio_sid_register_volume;
    const AUDIO_SID_REGISTER_READBACK = r4os.abi.audio_sid_register_readback;
    const AudioSidOp = r4os.abi.AudioSidOp;
};

const MEM_SIZE: usize = 65_536;
const REG_COUNT: usize = 25;
pub const RENDER_FRAMES: usize = SAMPLE_RATE / 50;
pub const RENDER_BYTES: usize = RENDER_FRAMES * 4;
const SAMPLE_RATE: u32 = 48_000;
const C64_PAL_CLOCK: u32 = 985_248;
const C64_PAL_RASTER_LINES: u64 = 312;
const C64_PAL_CYCLES_PER_LINE: u64 = 63;
const VOICE_COUNT: usize = 3;
const FILTER_MIN: i32 = -131_072;
const FILTER_MAX: i32 = 131_071;
const ENV_MAX: u32 = 0x7FFF_0000;
const ADSR_ATTACK_MS: [16]u32 = .{ 2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000 };
const ADSR_DECAY_RELEASE_MS: [16]u32 = .{ 6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000 };

const FLAG_C: u8 = 0x01;
const FLAG_Z: u8 = 0x02;
const FLAG_I: u8 = 0x04;
const FLAG_D: u8 = 0x08;
const FLAG_B: u8 = 0x10;
const FLAG_U: u8 = 0x20;
const FLAG_V: u8 = 0x40;
const FLAG_N: u8 = 0x80;

const StepEvent = enum {
    running,
    rts,
    brk,
    unsupported,
};

const Cpu = struct {
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    sp: u8 = 0xFF,
    p: u8 = FLAG_U | FLAG_I,
    pc: u16 = 0,
    cycles: u64 = 0,
};

const Voice = struct {
    phase: u32 = 0,
    envelope: u32 = 0,
    noise: u32 = 0x7FFFF8,
    gate: bool = false,
    releasing: bool = false,
    wrapped: bool = false,
};

const SidModel = enum {
    mos6581,
    mos8580,
};

pub const SidProtocolStatus = struct {
    source: []const u8 = "none",
    model: u64 = 0,
    register: u64 = 0,
    io: u64 = 0,
    missing_required: u64 = 0,
    dispatch_fail: u64 = 0,
    last_result: i32 = 0,
    last_kind: u8 = 0,
    last_voice: u8 = 0,
};

const FilterState = struct {
    low: i32 = 0,
    band: i32 = 0,
};

var memory: [MEM_SIZE]u8 = .{0} ** MEM_SIZE;
var registers: [REG_COUNT]u8 = .{0} ** REG_COUNT;
var voices: [VOICE_COUNT]Voice = .{Voice{}} ** VOICE_COUNT;
var cpu: Cpu = .{};
var register_writes: u64 = 0;
var last_register: u8 = 0;
var last_value: u8 = 0;
var cpu_steps: u64 = 0;
var call_count: u64 = 0;
var unsupported_count: u64 = 0;
var brk_count: u64 = 0;
var last_pc: u16 = 0;
var last_opcode: u8 = 0;
var last_error: []const u8 = "none";
var runtime_loaded: bool = false;
var runtime_load_addr: u16 = 0;
var runtime_data_len: u32 = 0;
var runtime_init_addr: u16 = 0;
var runtime_play_addr: u16 = 0;
var runtime_song: u8 = 0;
var runtime_frame_hz: u16 = 50;
var runtime_frames: u64 = 0;
var runtime_running: bool = false;
var runtime_last_steps: u32 = 0;
var runtime_step_limit_hits: u32 = 0;
var render_blocks: u64 = 0;
var render_frames: u64 = 0;
var last_sample: i16 = 0;
var last_mixed_voices: u8 = 0;
var last_master_volume: u8 = 0;
var sid_model: SidModel = .mos8580;
var filter_state: FilterState = .{};
var last_filter_cutoff: u16 = 0;
var last_filter_resonance: u8 = 0;
var last_filter_mode: u8 = 0;
var last_filter_route: u8 = 0;
var last_filter_sample: i16 = 0;
var last_direct_sample: i16 = 0;
var last_voice3_off: bool = false;
var last_d418_sample: i16 = 0;
var d418_decay_sample: i32 = 0;
var d418_write_count: u64 = 0;
var render_clip_events: u64 = 0;
var last_block_clip_events: u32 = 0;
var last_preclip_sample: i32 = 0;
var last_osc3_read: u8 = 0;
var last_env3_read: u8 = 0;
var last_potx_read: u8 = 0xFF;
var last_poty_read: u8 = 0xFF;
var last_raster_read: u16 = 0;
var last_cia_read: u8 = 0;
var last_io_read_addr: u16 = 0;
var last_io_read_value: u8 = 0;
var last_io_write_addr: u16 = 0;
var last_io_write_value: u8 = 0;
var sid_r4p_model: u64 = 0;
var sid_r4p_register: u64 = 0;
var sid_r4p_io: u64 = 0;
var sid_missing_required: u64 = 0;
var sid_dispatch_failures: u64 = 0;
var sid_last_result: i32 = 0;
var sid_last_kind: u8 = 0;
var sid_last_voice: u8 = 0;

pub fn bindProtocolDispatch(dispatch_fn: ?r4p.DispatchFn) bool {
    r4p.dispatch_fn = dispatch_fn;
    r4p.active = false;
    return dispatch_fn != null;
}

pub fn reset() void {
    clearMemory();
    clearRegisters();
    voices = .{Voice{}} ** VOICE_COUNT;
    cpu = .{};
    register_writes = 0;
    last_register = 0;
    last_value = 0;
    cpu_steps = 0;
    call_count = 0;
    unsupported_count = 0;
    brk_count = 0;
    last_pc = 0;
    last_opcode = 0;
    last_error = "none";
    runtime_loaded = false;
    runtime_load_addr = 0;
    runtime_data_len = 0;
    runtime_init_addr = 0;
    runtime_play_addr = 0;
    runtime_song = 0;
    runtime_frame_hz = 50;
    runtime_frames = 0;
    runtime_running = false;
    runtime_last_steps = 0;
    runtime_step_limit_hits = 0;
    render_blocks = 0;
    render_frames = 0;
    last_sample = 0;
    last_mixed_voices = 0;
    last_master_volume = 0;
    sid_model = .mos8580;
    filter_state = .{};
    last_filter_cutoff = 0;
    last_filter_resonance = 0;
    last_filter_mode = 0;
    last_filter_route = 0;
    last_filter_sample = 0;
    last_direct_sample = 0;
    last_voice3_off = false;
    last_d418_sample = 0;
    d418_decay_sample = 0;
    d418_write_count = 0;
    render_clip_events = 0;
    last_block_clip_events = 0;
    last_preclip_sample = 0;
    last_osc3_read = 0;
    last_env3_read = 0;
    last_potx_read = 0xFF;
    last_poty_read = 0xFF;
    last_raster_read = 0;
    last_cia_read = 0;
    last_io_read_addr = 0;
    last_io_read_value = 0;
    last_io_write_addr = 0;
    last_io_write_value = 0;
    sid_r4p_model = 0;
    sid_r4p_register = 0;
    sid_r4p_io = 0;
    sid_missing_required = 0;
    sid_dispatch_failures = 0;
    sid_last_result = 0;
    sid_last_kind = 0;
    sid_last_voice = 0;
}

pub fn configureModel(name: []const u8) bool {
    const requested = if (eqIgnoreCase(name, "6581") or eqIgnoreCase(name, "MOS6581"))
        r4p_contract.AUDIO_SID_MODEL_6581
    else if (eqIgnoreCase(name, "8580") or eqIgnoreCase(name, "MOS8580"))
        r4p_contract.AUDIO_SID_MODEL_8580
    else
        return false;
    if (classifySidModel(requested) == null) return false;
    if (requested == r4p_contract.AUDIO_SID_MODEL_6581) {
        sid_model = .mos6581;
    } else {
        sid_model = .mos8580;
    }
    return true;
}

pub fn modelNameZ() [*:0]const u8 {
    return switch (sid_model) {
        .mos6581 => "6581",
        .mos8580 => "8580",
    };
}

pub fn protocolStatus() SidProtocolStatus {
    return .{
        .source = r4p.requiredSourceName("audio.sid"),
        .model = sid_r4p_model,
        .register = sid_r4p_register,
        .io = sid_r4p_io,
        .missing_required = sid_missing_required,
        .dispatch_fail = sid_dispatch_failures,
        .last_result = sid_last_result,
        .last_kind = sid_last_kind,
        .last_voice = sid_last_voice,
    };
}

pub fn writeRegister(register: u8, value: u8) i32 {
    _ = classifySidRegister(register, value) orelse return -5;
    return writeRegisterDecoded(register, value);
}

fn writeRegisterDecoded(register: u8, value: u8) i32 {
    if (register >= REG_COUNT) return -1;
    const old_value = registers[register];
    registers[register] = value;
    last_register = register;
    last_value = value;
    register_writes += 1;
    sid_last_kind = localRegisterKind(register);
    sid_last_voice = if (register < 0x15) register / 7 else 0;
    if (register == 0x18) {
        noteD418Write(old_value, value);
        last_master_volume = value & 0x0F;
    }
    return 0;
}

pub fn renderBlock(out: []u8) bool {
    if (out.len < RENDER_BYTES) return false;
    const volume = registers[0x18] & 0x0F;
    last_master_volume = volume;
    const filter_route = registers[0x17] & 0x07;
    const filter_mode = (registers[0x18] >> 4) & 0x07;
    const voice3_off = (registers[0x18] & 0x80) != 0;
    last_voice3_off = voice3_off;
    last_filter_route = filter_route;
    last_filter_mode = filter_mode;
    last_filter_resonance = registers[0x17] >> 4;
    last_filter_cutoff = filterCutoff();
    last_block_clip_events = 0;

    var block_audible = false;
    var frame: usize = 0;
    while (frame < RENDER_FRAMES) : (frame += 1) {
        var direct_sum: i32 = 0;
        var filter_sum: i32 = 0;
        var direct_active: u8 = 0;
        var filter_active: u8 = 0;
        var audible_active: u8 = 0;
        var voice_index: usize = 0;
        while (voice_index < VOICE_COUNT) : (voice_index += 1) {
            const sample = renderVoice(voice_index);
            if (sample != 0) audible_active += 1;
            const routed = (filter_route & (@as(u8, 1) << @intCast(voice_index))) != 0;
            if (routed) {
                filter_sum += sample;
                if (sample != 0) filter_active += 1;
            } else if (!(voice3_off and voice_index == 2)) {
                direct_sum += sample;
                if (sample != 0) direct_active += 1;
            }
        }

        const direct = mixWithHeadroom(direct_sum, direct_active);
        const filter_input = mixWithHeadroom(filter_sum, filter_active);
        var filtered: i32 = 0;
        if (filter_route != 0 and filter_mode != 0) filtered = runFilter(filter_input, filter_mode);
        last_direct_sample = clampI16(direct);
        last_filter_sample = clampI16(filtered);
        const d418 = renderD418Sample();
        if (d418 != 0) block_audible = true;
        var mixed = direct + filtered;
        mixed = applyModelOutput(mixed);
        mixed = @divTrunc(mixed * @as(i32, volume), 15);
        mixed += d418;
        const sample_i16 = clampOutput(mixed);
        const bits: u16 = @bitCast(sample_i16);
        const off = frame * 4;
        out[off] = @intCast(bits & 0x00FF);
        out[off + 1] = @intCast((bits >> 8) & 0x00FF);
        out[off + 2] = out[off];
        out[off + 3] = out[off + 1];
        last_sample = sample_i16;
        last_mixed_voices = audible_active;
        if (sample_i16 != 0) block_audible = true;
    }

    render_blocks += 1;
    render_frames += RENDER_FRAMES;
    return block_audible;
}

pub fn loadProgram(load_addr: u16, data: []const u8) bool {
    if (@as(usize, load_addr) + data.len > memory.len) {
        last_error = "load-range";
        return false;
    }
    @memcpy(memory[@as(usize, load_addr) .. @as(usize, load_addr) + data.len], data);
    return true;
}

pub fn loadSidData(load_addr: u16, data: []const u8) bool {
    if (data.len == 0 or @as(usize, load_addr) + data.len > memory.len) {
        last_error = "sid-load-range";
        runtime_loaded = false;
        return false;
    }

    clearRuntimeState();
    @memcpy(memory[@as(usize, load_addr) .. @as(usize, load_addr) + data.len], data);
    runtime_loaded = true;
    runtime_load_addr = load_addr;
    runtime_data_len = @intCast(data.len);
    last_error = "none";
    return true;
}

pub fn callRoutine(addr: u16, max_steps: u32) bool {
    return callRoutineA(addr, 0, max_steps);
}

pub fn initSid(init_addr: u16, song: u16, max_steps: u32) bool {
    if (!runtime_loaded or init_addr == 0) {
        last_error = "sid-init-missing";
        return false;
    }
    runtime_init_addr = init_addr;
    runtime_song = if (song == 0) 0 else @intCast((song - 1) & 0x00FF);
    return callRoutineA(init_addr, runtime_song, max_steps);
}

pub fn playFrame(play_addr: u16, frame_hz: u16, max_steps: u32) bool {
    if (!runtime_loaded or play_addr == 0) {
        last_error = "sid-play-missing";
        return false;
    }
    runtime_play_addr = play_addr;
    runtime_frame_hz = if (frame_hz == 0) 50 else frame_hz;
    runtime_frames += 1;
    runtime_running = true;
    return callRoutineA(play_addr, 0, max_steps);
}

pub fn stopRuntime() void {
    runtime_running = false;
    last_error = "stopped";
}

fn callRoutineA(addr: u16, a_value: u8, max_steps: u32) bool {
    cpu = .{ .a = a_value, .pc = addr };
    call_count += 1;
    runtime_last_steps = 0;

    var steps: u32 = 0;
    while (steps < max_steps) : (steps += 1) {
        const event = step();
        runtime_last_steps = steps + 1;
        if (event == .running) continue;
        if (event == .rts) {
            last_error = "none";
            return true;
        }
        return false;
    }

    last_error = "step-limit";
    runtime_step_limit_hits += 1;
    return false;
}

pub fn dumpStatus() void {
    k.puts("SID:\r\n");
    k.puts("  core=yes calls=");
    k.putDec(call_count);
    k.puts(" cpu_steps=");
    k.putDec(cpu_steps);
    k.puts(" unsupported=");
    k.putDec(unsupported_count);
    k.puts(" brk=");
    k.putDec(brk_count);
    k.puts(" error=");
    k.puts(last_error);
    k.puts("\r\n");
    k.puts("  cpu: pc=0x");
    k.putHex(cpu.pc, 4);
    k.puts(" a=0x");
    k.putHex(cpu.a, 2);
    k.puts(" x=0x");
    k.putHex(cpu.x, 2);
    k.puts(" y=0x");
    k.putHex(cpu.y, 2);
    k.puts(" sp=0x");
    k.putHex(cpu.sp, 2);
    k.puts(" p=0x");
    k.putHex(cpu.p, 2);
    k.puts(" last=0x");
    k.putHex(last_pc, 4);
    k.putc('/');
    k.putHex(last_opcode, 2);
    k.puts("\r\n");
    k.puts("  registers: writes=");
    k.putDec(register_writes);
    k.puts(" last_reg=");
    k.putDec(last_register);
    k.puts(" last_val=");
    k.putDec(last_value);
    k.puts("\r\n");
    k.puts("  c64: loaded=");
    k.puts(if (runtime_loaded) "yes" else "no");
    k.puts(" load=0x");
    k.putHex(runtime_load_addr, 4);
    k.puts(" bytes=");
    k.putDec(runtime_data_len);
    k.puts(" init=0x");
    k.putHex(runtime_init_addr, 4);
    k.puts(" play=0x");
    k.putHex(runtime_play_addr, 4);
    k.puts(" running=");
    k.puts(if (runtime_running) "yes" else "no");
    k.puts(" song=");
    k.putDec(runtime_song);
    k.puts(" frame_hz=");
    k.putDec(runtime_frame_hz);
    k.puts(" frames=");
    k.putDec(runtime_frames);
    k.puts(" last_steps=");
    k.putDec(runtime_last_steps);
    k.puts(" limits=");
    k.putDec(runtime_step_limit_hits);
    k.puts("\r\n");
    k.puts("  render: blocks=");
    k.putDec(render_blocks);
    k.puts(" frames=");
    k.putDec(render_frames);
    k.puts(" voices=");
    k.putDec(last_mixed_voices);
    k.puts(" volume=");
    k.putDec(last_master_volume);
    k.puts(" sample=");
    printSigned(last_sample);
    k.puts("\r\n");
    k.puts("  filter: model=");
    k.puts(modelName());
    k.puts(" cutoff=");
    k.putDec(last_filter_cutoff);
    k.puts(" res=");
    k.putDec(last_filter_resonance);
    k.puts(" route=0x");
    k.putHex(last_filter_route, 2);
    k.puts(" mode=0x");
    k.putHex(last_filter_mode, 2);
    k.puts(" direct=");
    printSigned(last_direct_sample);
    k.puts(" filtered=");
    printSigned(last_filter_sample);
    k.puts(" voice3off=");
    k.puts(if (last_voice3_off) "yes" else "no");
    k.puts("\r\n");
    k.puts("  mix: d418=");
    printSigned(last_d418_sample);
    k.puts(" d418_writes=");
    k.putDec(d418_write_count);
    k.puts(" clips=");
    k.putDec(render_clip_events);
    k.puts(" block_clips=");
    k.putDec(last_block_clip_events);
    k.puts(" preclip=");
    printSigned32(last_preclip_sample);
    k.puts("\r\n");
    k.puts("  read: osc3=0x");
    k.putHex(last_osc3_read, 2);
    k.puts(" env3=0x");
    k.putHex(last_env3_read, 2);
    k.puts(" pot=0x");
    k.putHex(last_potx_read, 2);
    k.putc('/');
    k.putHex(last_poty_read, 2);
    k.puts(" raster=");
    k.putDec(last_raster_read);
    k.puts(" cia=0x");
    k.putHex(last_cia_read, 2);
    k.puts("\r\n");
    k.puts("  io: read=0x");
    k.putHex(last_io_read_addr, 4);
    k.putc('/');
    k.putHex(last_io_read_value, 2);
    k.puts(" write=0x");
    k.putHex(last_io_write_addr, 4);
    k.putc('/');
    k.putHex(last_io_write_value, 2);
    k.puts("\r\n");
    k.puts("  protocol: source=");
    k.puts(r4p.requiredSourceName("audio.sid"));
    k.puts(" model=");
    k.putDec(sid_r4p_model);
    k.puts(" reg=");
    k.putDec(sid_r4p_register);
    k.puts(" io=");
    k.putDec(sid_r4p_io);
    k.puts(" required_missing=");
    k.putDec(sid_missing_required);
    k.puts(" fail=");
    k.putDec(sid_dispatch_failures);
    k.puts(" kind=");
    k.putDec(sid_last_kind);
    k.puts(" voice=");
    k.putDec(sid_last_voice);
    k.puts("\r\n");
}

fn classifySidModel(model: u8) ?r4p_contract.AudioSidOp {
    if (classifySidModelR4p(model)) |op| return op;
    sid_missing_required +%= 1;
    sid_last_result = -5;
    return null;
}

fn classifySidModelR4p(model: u8) ?r4p_contract.AudioSidOp {
    if (!r4p.hasActiveR4p("audio.sid")) return null;
    var op = r4p_contract.AudioSidOp{ .model = model };
    if (!dispatchSid(r4p_contract.AUDIO_SID_OP_CONFIGURE_MODEL, &op) or op.result != r4p_contract.AUDIO_SID_RESULT_OK) return null;
    sid_r4p_model +%= 1;
    return op;
}

fn classifySidRegister(register: u8, value: u8) ?r4p_contract.AudioSidOp {
    if (classifySidRegisterR4p(register, value)) |op| {
        sid_last_kind = op.kind;
        sid_last_voice = op.voice;
        return op;
    }
    sid_missing_required +%= 1;
    sid_last_result = -5;
    sid_last_kind = r4p_contract.AUDIO_SID_REGISTER_OTHER;
    sid_last_voice = 0;
    return null;
}

fn classifySidRegisterR4p(register: u8, value: u8) ?r4p_contract.AudioSidOp {
    if (!r4p.hasActiveR4p("audio.sid")) return null;
    var op = r4p_contract.AudioSidOp{
        .register = register,
        .value = value,
    };
    if (!dispatchSid(r4p_contract.AUDIO_SID_OP_WRITE_REGISTER, &op) or op.result != r4p_contract.AUDIO_SID_RESULT_OK) return null;
    sid_r4p_register +%= 1;
    sid_last_kind = op.kind;
    sid_last_voice = op.voice;
    return op;
}

fn resolveSidIoAddress(address: u16, value: u8) ?r4p_contract.AudioSidOp {
    if (resolveSidIoAddressR4p(address, value)) |op| {
        sid_last_kind = op.kind;
        sid_last_voice = op.voice;
        return op;
    }
    sid_missing_required +%= 1;
    sid_last_result = -5;
    sid_last_kind = r4p_contract.AUDIO_SID_REGISTER_OTHER;
    sid_last_voice = 0;
    return null;
}

fn resolveSidIoAddressR4p(address: u16, value: u8) ?r4p_contract.AudioSidOp {
    if (!r4p.hasActiveR4p("audio.sid")) return null;
    var op = r4p_contract.AudioSidOp{
        .address = address,
        .value = value,
    };
    if (!dispatchSid(r4p_contract.AUDIO_SID_OP_RESOLVE_IO, &op) or op.result != r4p_contract.AUDIO_SID_RESULT_OK) return null;
    sid_r4p_io +%= 1;
    sid_last_kind = op.kind;
    sid_last_voice = op.voice;
    return op;
}

fn dispatchSid(opcode: u32, op: *r4p_contract.AudioSidOp) bool {
    var buffer = protocol_api.ProtocolBuffer{
        .data = op,
        .len = @sizeOf(r4p_contract.AudioSidOp),
        .capacity = @sizeOf(r4p_contract.AudioSidOp),
        .flags = 0,
        .reserved = 0,
    };
    var out: protocol_api.ProtocolBuffer = .{};
    const result = r4p.dispatch("audio.sid", opcode, &buffer, &out);
    sid_last_result = result;
    if (result != r4p_contract.AUDIO_SID_RESULT_OK) {
        sid_dispatch_failures +%= 1;
        return false;
    }
    return true;
}

fn resetProtocolCounters() void {
    sid_r4p_model = 0;
    sid_r4p_register = 0;
    sid_r4p_io = 0;
    sid_missing_required = 0;
    sid_dispatch_failures = 0;
    sid_last_result = 0;
    sid_last_kind = 0;
    sid_last_voice = 0;
}

fn clearRuntimeState() void {
    initC64Defaults();
    clearRegisters();
    cpu = .{};
    register_writes = 0;
    last_register = 0;
    last_value = 0;
    voices = .{Voice{}} ** VOICE_COUNT;
    runtime_loaded = false;
    runtime_load_addr = 0;
    runtime_data_len = 0;
    runtime_init_addr = 0;
    runtime_play_addr = 0;
    runtime_song = 0;
    runtime_frame_hz = 50;
    runtime_frames = 0;
    runtime_running = false;
    runtime_last_steps = 0;
    runtime_step_limit_hits = 0;
    render_blocks = 0;
    render_frames = 0;
    last_sample = 0;
    last_mixed_voices = 0;
    last_master_volume = 0;
    filter_state = .{};
    last_filter_cutoff = 0;
    last_filter_resonance = 0;
    last_filter_mode = 0;
    last_filter_route = 0;
    last_filter_sample = 0;
    last_direct_sample = 0;
    last_voice3_off = false;
    last_d418_sample = 0;
    d418_decay_sample = 0;
    d418_write_count = 0;
    render_clip_events = 0;
    last_block_clip_events = 0;
    last_preclip_sample = 0;
    last_osc3_read = 0;
    last_env3_read = 0;
    last_potx_read = 0xFF;
    last_poty_read = 0xFF;
    last_raster_read = 0;
    last_cia_read = 0;
    last_io_read_addr = 0;
    last_io_read_value = 0;
    last_io_write_addr = 0;
    last_io_write_value = 0;
}

fn clearMemory() void {
    var i: usize = 0;
    while (i < memory.len) : (i += 1) memory[i] = 0;
}

fn clearRegisters() void {
    var i: usize = 0;
    while (i < registers.len) : (i += 1) registers[i] = 0;
}

fn initC64Defaults() void {
    memory[0x0000] = 0x2F;
    memory[0x0001] = 0x37;
    memory[0xDC00] = 0xFF;
    memory[0xDC01] = 0xFF;
    memory[0xDD00] = 0xFF;
    memory[0xDD01] = 0xFF;
}

fn renderVoice(index: usize) i32 {
    const base = index * 7;
    const freq = @as(u16, registers[base]) | (@as(u16, registers[base + 1]) << 8);
    const pulse = (@as(u16, registers[base + 2]) | (@as(u16, registers[base + 3] & 0x0F) << 8));
    const control = registers[base + 4];
    const gate = (control & 0x01) != 0;
    if (gate and !voices[index].gate) {
        voices[index].releasing = false;
    } else if (!gate and voices[index].gate) {
        voices[index].releasing = true;
    }
    voices[index].gate = gate;

    const attack_decay = registers[base + 5];
    const sustain_release = registers[base + 6];
    const sustain = (@as(u32, sustain_release >> 4) * 0x0888) << 16;

    if ((control & 0x08) != 0) {
        voices[index].phase = 0;
        voices[index].noise = 0x7FFFF8;
        voices[index].wrapped = false;
        return 0;
    }

    if (freq == 0 or !gate) {
        const release_step = decayReleaseStep(sustain_release & 0x0F);
        if (voices[index].envelope > release_step) {
            voices[index].envelope -= release_step;
        } else {
            voices[index].envelope = 0;
        }
    } else if (voices[index].envelope < ENV_MAX and !voices[index].releasing) {
        const attack_step = attackStep(attack_decay >> 4);
        voices[index].envelope = addSatEnv(voices[index].envelope, attack_step);
    } else if (voices[index].envelope > sustain) {
        const decay_step = decayReleaseStep(attack_decay & 0x0F);
        if (voices[index].envelope > sustain + decay_step) {
            voices[index].envelope -= decay_step;
        } else {
            voices[index].envelope = sustain;
        }
    }
    if (voices[index].envelope == 0) return 0;

    const increment: u32 = @intCast((@as(u64, freq) * C64_PAL_CLOCK) / SAMPLE_RATE);
    const old_phase = voices[index].phase;
    if ((control & 0x02) != 0 and voices[prevVoice(index)].wrapped) voices[index].phase = 0;
    voices[index].phase = (voices[index].phase +% increment) & 0x00FF_FFFF;
    voices[index].wrapped = voices[index].phase < old_phase;
    const sample = waveformSample(index, control, pulse);

    const env_level: i32 = @intCast(voices[index].envelope >> 16);
    return @divTrunc(sample * env_level, 0x7FFF);
}

fn waveformSample(index: usize, control: u8, pulse: u16) i32 {
    const waveform_select = control & 0xF0;
    const phase16: u16 = @intCast((voices[index].phase >> 8) & 0xFFFF);
    if (waveform_select == 0) return 0;

    var bits: u16 = 0xFFFF;
    if ((control & 0x80) != 0) {
        voices[index].noise = nextNoise(voices[index].noise);
        bits &= noiseWaveBits(voices[index].noise);
    }
    if ((control & 0x40) != 0) bits &= pulseWaveBits(voices[index].phase, pulse);
    if ((control & 0x20) != 0) bits &= phase16;
    if ((control & 0x10) != 0) {
        var tri = triangleWaveBits(phase16);
        if ((control & 0x04) != 0 and (voices[prevVoice(index)].phase & 0x0080_0000) != 0) tri ^= 0xFFFF;
        bits &= tri;
    }
    return unsignedWaveToSigned(bits);
}

fn oscillatorRead(index: usize) u8 {
    const base = index * 7;
    const control = registers[base + 4];
    const pulse = (@as(u16, registers[base + 2]) | (@as(u16, registers[base + 3] & 0x0F) << 8));
    const phase16: u16 = @intCast((voices[index].phase >> 8) & 0xFFFF);
    const waveform_select = control & 0xF0;
    var bits: u16 = if (waveform_select == 0) phase16 else 0xFFFF;
    if ((control & 0x80) != 0) bits &= noiseWaveBits(voices[index].noise);
    if ((control & 0x40) != 0) bits &= pulseWaveBits(voices[index].phase, pulse);
    if ((control & 0x20) != 0) bits &= phase16;
    if ((control & 0x10) != 0) {
        var tri = triangleWaveBits(phase16);
        if ((control & 0x04) != 0 and (voices[prevVoice(index)].phase & 0x0080_0000) != 0) tri ^= 0xFFFF;
        bits &= tri;
    }
    return @intCast((bits >> 8) & 0x00FF);
}

fn envelopeRead(index: usize) u8 {
    const env_level: u32 = voices[index].envelope >> 16;
    return @intCast((env_level >> 7) & 0x00FF);
}

fn triangleWaveBits(phase16: u16) u16 {
    const saw: u32 = phase16;
    const tri = if (saw < 32768) saw * 2 else (65535 - saw) * 2;
    return @intCast(tri & 0xFFFF);
}

fn pulseWaveBits(phase: u32, pulse: u16) u16 {
    const threshold = pulse & 0x0FFF;
    const phase12 = (phase >> 12) & 0x0FFF;
    return if (phase12 < threshold) 0xFFFF else 0;
}

fn noiseWaveBits(state: u32) u16 {
    var out: u16 = 0;
    out |= @as(u16, @intCast((state >> 22) & 1)) << 7;
    out |= @as(u16, @intCast((state >> 20) & 1)) << 6;
    out |= @as(u16, @intCast((state >> 16) & 1)) << 5;
    out |= @as(u16, @intCast((state >> 13) & 1)) << 4;
    out |= @as(u16, @intCast((state >> 11) & 1)) << 3;
    out |= @as(u16, @intCast((state >> 7) & 1)) << 2;
    out |= @as(u16, @intCast((state >> 4) & 1)) << 1;
    out |= @as(u16, @intCast((state >> 2) & 1));
    return out * 0x0101;
}

fn unsignedWaveToSigned(value: u16) i32 {
    return @as(i32, @intCast(value)) - 32768;
}

fn mixWithHeadroom(sample: i32, active: u8) i32 {
    return switch (active) {
        0, 1 => sample,
        2 => @divTrunc(sample * 2, 3),
        else => @divTrunc(sample, 2),
    };
}

fn localRegisterKind(register: u8) u8 {
    if (register < 0x15) return r4p_contract.AUDIO_SID_REGISTER_VOICE;
    if (register >= 0x15 and register <= 0x17) return r4p_contract.AUDIO_SID_REGISTER_FILTER;
    if (register == 0x18) return r4p_contract.AUDIO_SID_REGISTER_VOLUME;
    if (register == 0x1B or register == 0x1C) return r4p_contract.AUDIO_SID_REGISTER_READBACK;
    return r4p_contract.AUDIO_SID_REGISTER_OTHER;
}

fn noteD418Write(old_value: u8, new_value: u8) void {
    const old_volume: i32 = old_value & 0x0F;
    const new_volume: i32 = new_value & 0x0F;
    const delta = new_volume - old_volume;
    if (delta == 0) return;
    d418_write_count += 1;
    const gain: i32 = switch (sid_model) {
        .mos6581 => 1100,
        .mos8580 => 260,
    };
    d418_decay_sample = clampD418(d418_decay_sample + delta * gain);
}

fn renderD418Sample() i32 {
    const value = d418_decay_sample;
    last_d418_sample = clampI16(value);
    if (d418_decay_sample > 0) {
        d418_decay_sample = @divTrunc(d418_decay_sample * 31, 32);
        if (d418_decay_sample < 16) d418_decay_sample = 0;
    } else if (d418_decay_sample < 0) {
        d418_decay_sample = @divTrunc(d418_decay_sample * 31, 32);
        if (d418_decay_sample > -16) d418_decay_sample = 0;
    }
    return value;
}

fn clampD418(value: i32) i32 {
    if (value > 24_000) return 24_000;
    if (value < -24_000) return -24_000;
    return value;
}

fn applyModelOutput(value: i32) i32 {
    return switch (sid_model) {
        .mos6581 => softClip(value),
        .mos8580 => @divTrunc(value * 7, 8),
    };
}

fn attackStep(nibble: u8) u32 {
    return rateStep(nibble, &ADSR_ATTACK_MS);
}

fn decayReleaseStep(nibble: u8) u32 {
    return rateStep(nibble, &ADSR_DECAY_RELEASE_MS);
}

fn rateStep(nibble: u8, table: *const [16]u32) u32 {
    const idx: usize = @intCast(nibble & 0x0F);
    const frames = @divTrunc(table[idx] * SAMPLE_RATE, 1000);
    if (frames == 0) return ENV_MAX;
    const amount = @divTrunc(ENV_MAX, frames);
    return if (amount == 0) 1 else amount;
}

fn addSatEnv(value: u32, amount: u32) u32 {
    const sum = value +| amount;
    return if (sum > ENV_MAX) ENV_MAX else sum;
}

fn prevVoice(index: usize) usize {
    return if (index == 0) VOICE_COUNT - 1 else index - 1;
}

fn runFilter(input_raw: i32, mode: u8) i32 {
    var input = input_raw;
    if (sid_model == .mos6581) input = softClip(@divTrunc(input * 5, 4));

    const cutoff_step = filterStep(last_filter_cutoff);
    const damping = filterDamping(last_filter_resonance);
    const high = input - filter_state.low - @divTrunc(filter_state.band * damping, 1024);
    const band_delta: i32 = @intCast(@divTrunc(@as(i64, high) * cutoff_step, 2048));
    filter_state.band = clampFilter(filter_state.band + band_delta);
    const low_delta: i32 = @intCast(@divTrunc(@as(i64, filter_state.band) * cutoff_step, 2048));
    filter_state.low = clampFilter(filter_state.low + low_delta);

    var out: i32 = 0;
    if ((mode & 0x01) != 0) out += filter_state.low;
    if ((mode & 0x02) != 0) out += filter_state.band;
    if ((mode & 0x04) != 0) out += high;
    if (sid_model == .mos6581) out = softClip(out);
    return out;
}

fn filterCutoff() u16 {
    return (@as(u16, registers[0x16]) << 3) | @as(u16, registers[0x15] & 0x07);
}

fn filterStep(cutoff: u16) i32 {
    const cutoff_i: i32 = @intCast(cutoff);
    return switch (sid_model) {
        .mos8580 => 64 + cutoff_i,
        .mos6581 => 48 + @divTrunc(cutoff_i * cutoff_i, 2048),
    };
}

fn filterDamping(resonance: u8) i32 {
    const base: i32 = switch (sid_model) {
        .mos8580 => 1024,
        .mos6581 => 896,
    };
    const amount = @as(i32, resonance) * 44;
    return if (base > amount + 160) base - amount else 160;
}

fn clampFilter(value: i32) i32 {
    if (value > FILTER_MAX) return FILTER_MAX;
    if (value < FILTER_MIN) return FILTER_MIN;
    return value;
}

fn softClip(value: i32) i32 {
    if (value > 28_000) return 28_000 + @divTrunc(value - 28_000, 4);
    if (value < -28_000) return -28_000 + @divTrunc(value + 28_000, 4);
    return value;
}

fn modelName() []const u8 {
    return switch (sid_model) {
        .mos6581 => "6581",
        .mos8580 => "8580",
    };
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (upper(a[i]) != upper(b[i])) return false;
    }
    return true;
}

fn upper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - ('a' - 'A');
    return c;
}

fn nextNoise(state: u32) u32 {
    const feedback_bit = ((state >> 22) ^ (state >> 17)) & 1;
    return ((state << 1) | feedback_bit) & 0x7FFFFF;
}

fn clampI16(value: i32) i16 {
    if (value > 32767) return 32767;
    if (value < -32768) return -32768;
    return @intCast(value);
}

fn clampOutput(value: i32) i16 {
    last_preclip_sample = value;
    if (value > 32767) {
        render_clip_events += 1;
        last_block_clip_events += 1;
        return 32767;
    }
    if (value < -32768) {
        render_clip_events += 1;
        last_block_clip_events += 1;
        return -32768;
    }
    return @intCast(value);
}

fn printSigned(value: i16) void {
    if (value < 0) {
        k.putc('-');
        k.putDec(@intCast(-value));
    } else {
        k.putDec(@intCast(value));
    }
}

fn printSigned32(value: i32) void {
    if (value < 0) {
        k.putc('-');
        k.putDec(@intCast(-value));
    } else {
        k.putDec(@intCast(value));
    }
}

fn step() StepEvent {
    last_pc = cpu.pc;
    const opcode = fetch();
    last_opcode = opcode;
    cpu_steps += 1;

    switch (opcode) {
        0x00 => {
            setFlag(FLAG_B, true);
            brk_count += 1;
            last_error = "brk";
            return .brk;
        },
        0x01 => ora(read(addrIndX())),
        0x04 => nopRead(addrZp()),
        0x05 => ora(read(addrZp())),
        0x06 => aslMem(addrZp()),
        0x08 => push(cpu.p | FLAG_B | FLAG_U),
        0x09 => ora(fetch()),
        0x0A => cpu.a = aslValue(cpu.a),
        0x0C => nopRead(addrAbs()),
        0x0D => ora(read(addrAbs())),
        0x0E => aslMem(addrAbs()),
        0x10 => branch(!flag(FLAG_N)),
        0x11 => ora(read(addrIndY())),
        0x14 => nopRead(addrZpX()),
        0x15 => ora(read(addrZpX())),
        0x16 => aslMem(addrZpX()),
        0x18 => setFlag(FLAG_C, false),
        0x19 => ora(read(addrAbsY())),
        0x1A => {},
        0x1C => nopRead(addrAbsX()),
        0x1D => ora(read(addrAbsX())),
        0x1E => aslMem(addrAbsX()),
        0x20 => jsr(),
        0x21 => andOp(read(addrIndX())),
        0x24 => bit(read(addrZp())),
        0x25 => andOp(read(addrZp())),
        0x26 => rolMem(addrZp()),
        0x28 => cpu.p = (pull() | FLAG_U) & ~FLAG_B,
        0x29 => andOp(fetch()),
        0x2A => cpu.a = rolValue(cpu.a),
        0x2C => bit(read(addrAbs())),
        0x2D => andOp(read(addrAbs())),
        0x2E => rolMem(addrAbs()),
        0x30 => branch(flag(FLAG_N)),
        0x31 => andOp(read(addrIndY())),
        0x34 => nopRead(addrZpX()),
        0x35 => andOp(read(addrZpX())),
        0x36 => rolMem(addrZpX()),
        0x38 => setFlag(FLAG_C, true),
        0x39 => andOp(read(addrAbsY())),
        0x3A => {},
        0x3C => nopRead(addrAbsX()),
        0x3D => andOp(read(addrAbsX())),
        0x3E => rolMem(addrAbsX()),
        0x40 => rti(),
        0x41 => eor(read(addrIndX())),
        0x44 => nopRead(addrZp()),
        0x45 => eor(read(addrZp())),
        0x46 => lsrMem(addrZp()),
        0x48 => push(cpu.a),
        0x49 => eor(fetch()),
        0x4A => cpu.a = lsrValue(cpu.a),
        0x4C => cpu.pc = fetch16(),
        0x4D => eor(read(addrAbs())),
        0x4E => lsrMem(addrAbs()),
        0x50 => branch(!flag(FLAG_V)),
        0x51 => eor(read(addrIndY())),
        0x54 => nopRead(addrZpX()),
        0x55 => eor(read(addrZpX())),
        0x56 => lsrMem(addrZpX()),
        0x58 => setFlag(FLAG_I, false),
        0x59 => eor(read(addrAbsY())),
        0x5A => {},
        0x5C => nopRead(addrAbsX()),
        0x5D => eor(read(addrAbsX())),
        0x5E => lsrMem(addrAbsX()),
        0x60 => {
            cpu.pc = pull16() +% 1;
            return .rts;
        },
        0x61 => adc(read(addrIndX())),
        0x64 => nopRead(addrZp()),
        0x65 => adc(read(addrZp())),
        0x66 => rorMem(addrZp()),
        0x68 => {
            cpu.a = pull();
            setZN(cpu.a);
        },
        0x69 => adc(fetch()),
        0x6A => cpu.a = rorValue(cpu.a),
        0x6C => cpu.pc = read16Bug(fetch16()),
        0x6D => adc(read(addrAbs())),
        0x6E => rorMem(addrAbs()),
        0x70 => branch(flag(FLAG_V)),
        0x71 => adc(read(addrIndY())),
        0x74 => nopRead(addrZpX()),
        0x75 => adc(read(addrZpX())),
        0x76 => rorMem(addrZpX()),
        0x78 => setFlag(FLAG_I, true),
        0x79 => adc(read(addrAbsY())),
        0x7A => {},
        0x7C => nopRead(addrAbsX()),
        0x7D => adc(read(addrAbsX())),
        0x80 => {
            _ = fetch();
        },
        0x7E => rorMem(addrAbsX()),
        0x81 => sta(addrIndX()),
        0x82 => {
            _ = fetch();
        },
        0x84 => sty(addrZp()),
        0x85 => sta(addrZp()),
        0x86 => stx(addrZp()),
        0x88 => {
            cpu.y -%= 1;
            setZN(cpu.y);
        },
        0x89 => {
            _ = fetch();
        },
        0x8A => {
            cpu.a = cpu.x;
            setZN(cpu.a);
        },
        0x8C => sty(addrAbs()),
        0x8D => sta(addrAbs()),
        0x8E => stx(addrAbs()),
        0x90 => branch(!flag(FLAG_C)),
        0x91 => sta(addrIndY()),
        0x94 => sty(addrZpX()),
        0x95 => sta(addrZpX()),
        0x96 => stx(addrZpY()),
        0x98 => {
            cpu.a = cpu.y;
            setZN(cpu.a);
        },
        0x99 => sta(addrAbsY()),
        0x9A => cpu.sp = cpu.x,
        0x9D => sta(addrAbsX()),
        0xA0 => ldy(fetch()),
        0xA1 => lda(read(addrIndX())),
        0xA2 => ldx(fetch()),
        0xA4 => ldy(read(addrZp())),
        0xA5 => lda(read(addrZp())),
        0xA6 => ldx(read(addrZp())),
        0xA8 => {
            cpu.y = cpu.a;
            setZN(cpu.y);
        },
        0xA9 => lda(fetch()),
        0xAA => {
            cpu.x = cpu.a;
            setZN(cpu.x);
        },
        0xAC => ldy(read(addrAbs())),
        0xAD => lda(read(addrAbs())),
        0xAE => ldx(read(addrAbs())),
        0xB0 => branch(flag(FLAG_C)),
        0xB1 => lda(read(addrIndY())),
        0xB4 => ldy(read(addrZpX())),
        0xB5 => lda(read(addrZpX())),
        0xB6 => ldx(read(addrZpY())),
        0xB8 => setFlag(FLAG_V, false),
        0xB9 => lda(read(addrAbsY())),
        0xBA => {
            cpu.x = cpu.sp;
            setZN(cpu.x);
        },
        0xBC => ldy(read(addrAbsX())),
        0xBD => lda(read(addrAbsX())),
        0xBE => ldx(read(addrAbsY())),
        0xC0 => cmp(cpu.y, fetch()),
        0xC1 => cmp(cpu.a, read(addrIndX())),
        0xC2 => {
            _ = fetch();
        },
        0xC4 => cmp(cpu.y, read(addrZp())),
        0xC5 => cmp(cpu.a, read(addrZp())),
        0xC6 => decMem(addrZp()),
        0xC8 => {
            cpu.y +%= 1;
            setZN(cpu.y);
        },
        0xC9 => cmp(cpu.a, fetch()),
        0xCA => {
            cpu.x -%= 1;
            setZN(cpu.x);
        },
        0xCC => cmp(cpu.y, read(addrAbs())),
        0xCD => cmp(cpu.a, read(addrAbs())),
        0xCE => decMem(addrAbs()),
        0xD0 => branch(!flag(FLAG_Z)),
        0xD1 => cmp(cpu.a, read(addrIndY())),
        0xD4 => nopRead(addrZpX()),
        0xD5 => cmp(cpu.a, read(addrZpX())),
        0xD6 => decMem(addrZpX()),
        0xD8 => setFlag(FLAG_D, false),
        0xD9 => cmp(cpu.a, read(addrAbsY())),
        0xDA => {},
        0xDC => nopRead(addrAbsX()),
        0xDD => cmp(cpu.a, read(addrAbsX())),
        0xDE => decMem(addrAbsX()),
        0xE0 => cmp(cpu.x, fetch()),
        0xE1 => sbc(read(addrIndX())),
        0xE2 => {
            _ = fetch();
        },
        0xE4 => cmp(cpu.x, read(addrZp())),
        0xE5 => sbc(read(addrZp())),
        0xE6 => incMem(addrZp()),
        0xE8 => {
            cpu.x +%= 1;
            setZN(cpu.x);
        },
        0xE9 => sbc(fetch()),
        0xEA => {},
        0xEC => cmp(cpu.x, read(addrAbs())),
        0xED => sbc(read(addrAbs())),
        0xEE => incMem(addrAbs()),
        0xF0 => branch(flag(FLAG_Z)),
        0xF1 => sbc(read(addrIndY())),
        0xF4 => nopRead(addrZpX()),
        0xF5 => sbc(read(addrZpX())),
        0xF6 => incMem(addrZpX()),
        0xF8 => setFlag(FLAG_D, true),
        0xF9 => sbc(read(addrAbsY())),
        0xFA => {},
        0xFC => nopRead(addrAbsX()),
        0xFD => sbc(read(addrAbsX())),
        0xFE => incMem(addrAbsX()),
        else => {
            unsupported_count += 1;
            last_error = "unsupported-opcode";
            return .unsupported;
        },
    }

    cpu.cycles += 1;
    return .running;
}

fn fetch() u8 {
    const value = read(cpu.pc);
    cpu.pc +%= 1;
    return value;
}

fn fetch16() u16 {
    const lo = fetch();
    const hi = fetch();
    return (@as(u16, hi) << 8) | lo;
}

fn read(addr: u16) u8 {
    if (addr >= 0xD000 and addr <= 0xD3FF) return traceIoRead(addr, readVic(addr));
    if (addr >= 0xD400 and addr <= 0xD7FF) return traceIoRead(addr, readSid(addr));
    if (addr >= 0xDC00 and addr <= 0xDDFF) return traceIoRead(addr, readCia(addr));
    return memory[addr];
}

fn write(addr: u16, value: u8) void {
    if (addr >= 0xD000 and addr <= 0xD3FF) {
        traceIoWrite(addr, value);
        writeVic(addr, value);
        return;
    }
    if (addr >= 0xD400 and addr <= 0xD7FF) {
        traceIoWrite(addr, value);
        writeSid(addr, value);
        return;
    }
    if (addr >= 0xDC00 and addr <= 0xDDFF) {
        traceIoWrite(addr, value);
        writeCia(addr, value);
        return;
    }
    memory[addr] = value;
}

fn traceIoRead(addr: u16, value: u8) u8 {
    last_io_read_addr = addr;
    last_io_read_value = value;
    return value;
}

fn traceIoWrite(addr: u16, value: u8) void {
    last_io_write_addr = addr;
    last_io_write_value = value;
}

fn readSid(addr: u16) u8 {
    const reg = sidMirrorRegister(addr);
    if (reg == 0x19) {
        last_potx_read = 0xFF;
        return last_potx_read;
    }
    if (reg == 0x1A) {
        last_poty_read = 0xFF;
        return last_poty_read;
    }
    if (reg == 0x1B) {
        last_osc3_read = oscillatorRead(2);
        return last_osc3_read;
    }
    if (reg == 0x1C) {
        last_env3_read = envelopeRead(2);
        return last_env3_read;
    }
    if (reg < REG_COUNT) return memory[0xD400 + @as(u16, reg)];
    return 0xFF;
}

fn writeSid(addr: u16, value: u8) void {
    const resolved = resolveSidIoAddress(addr, value) orelse return;
    const reg = resolved.register;
    memory[addr] = value;
    if (reg < REG_COUNT) {
        memory[0xD400 + @as(u16, reg)] = value;
        _ = writeRegisterDecoded(reg, value);
    }
}

fn sidMirrorRegister(addr: u16) u8 {
    return @intCast((addr - 0xD400) & 0x001F);
}

fn readVic(addr: u16) u8 {
    const reg_addr: u16 = 0xD000 | (addr & 0x003F);
    const raster = currentRaster();
    last_raster_read = raster;
    if (reg_addr == 0xD011) return (memory[reg_addr] & 0x7F) | @as(u8, if ((raster & 0x0100) != 0) 0x80 else 0);
    if (reg_addr == 0xD012) return @intCast(raster & 0x00FF);
    if (reg_addr == 0xD019) {
        const compare = @as(u16, memory[0xD012]) | (@as(u16, memory[0xD011] & 0x80) << 1);
        if (raster == compare) memory[reg_addr] |= 0x01;
        return memory[reg_addr];
    }
    return memory[reg_addr];
}

fn writeVic(addr: u16, value: u8) void {
    const reg_addr: u16 = 0xD000 | (addr & 0x003F);
    if (reg_addr == 0xD019) {
        memory[reg_addr] &= ~value;
    } else {
        memory[reg_addr] = value;
    }
}

fn readCia(addr: u16) u8 {
    const base: u16 = addr & 0xFF00;
    const reg: u8 = @intCast(addr & 0x000F);
    const reg_addr = base | @as(u16, reg);
    const value = switch (reg) {
        0x00, 0x01 => ciaPortRead(reg_addr),
        0x04 => ciaTimerByte(base, 0, false),
        0x05 => ciaTimerByte(base, 0, true),
        0x06 => ciaTimerByte(base, 1, false),
        0x07 => ciaTimerByte(base, 1, true),
        0x0D => memory[reg_addr] | 0x80,
        else => memory[reg_addr],
    };
    last_cia_read = value;
    return value;
}

fn ciaPortRead(reg_addr: u16) u8 {
    const value = memory[reg_addr];
    return if (value == 0) 0xFF else value;
}

fn writeCia(addr: u16, value: u8) void {
    const base: u16 = addr & 0xFF00;
    const reg: u16 = addr & 0x000F;
    const reg_addr = base | reg;
    memory[reg_addr] = if (reg == 0x000D) value & 0x7F else value;
}

fn ciaTimerByte(base: u16, timer: u8, high: bool) u8 {
    const offset: u16 = if (timer == 0) 0x04 else 0x06;
    const control_offset: u16 = if (timer == 0) 0x0E else 0x0F;
    const lo_addr = base + offset;
    const hi_addr = lo_addr + 1;
    const control = memory[base + control_offset];
    const latch = (@as(u16, memory[hi_addr]) << 8) | memory[lo_addr];
    const period: u32 = if (latch == 0) 0x10000 else latch;
    var current: u16 = latch;
    if ((control & 0x01) != 0) {
        const elapsed: u32 = @intCast(cpu.cycles % period);
        current = @intCast((period - 1 - elapsed) & 0xFFFF);
    }
    return if (high) @intCast((current >> 8) & 0x00FF) else @intCast(current & 0x00FF);
}

fn currentRaster() u16 {
    const frame = if (runtime_frames == 0) 0 else runtime_frames - 1;
    const line = (frame + @divTrunc(cpu.cycles, C64_PAL_CYCLES_PER_LINE)) % C64_PAL_RASTER_LINES;
    return @intCast(line);
}

fn read16(addr: u16) u16 {
    return (@as(u16, read(addr +% 1)) << 8) | read(addr);
}

fn read16Bug(addr: u16) u16 {
    const next = (addr & 0xFF00) | @as(u16, @intCast((addr +% 1) & 0x00FF));
    return (@as(u16, read(next)) << 8) | read(addr);
}

fn addrZp() u16 {
    return fetch();
}

fn addrZpX() u16 {
    return @as(u8, @truncate(fetch() +% cpu.x));
}

fn addrZpY() u16 {
    return @as(u8, @truncate(fetch() +% cpu.y));
}

fn addrAbs() u16 {
    return fetch16();
}

fn addrAbsX() u16 {
    return fetch16() +% cpu.x;
}

fn addrAbsY() u16 {
    return fetch16() +% cpu.y;
}

fn addrIndX() u16 {
    const zp: u8 = @truncate(fetch() +% cpu.x);
    return (@as(u16, read(@as(u8, zp +% 1))) << 8) | read(zp);
}

fn addrIndY() u16 {
    const zp = fetch();
    const base = (@as(u16, read(@as(u8, zp +% 1))) << 8) | read(zp);
    return base +% cpu.y;
}

fn push(value: u8) void {
    write(0x0100 | @as(u16, cpu.sp), value);
    cpu.sp -%= 1;
}

fn pull() u8 {
    cpu.sp +%= 1;
    return read(0x0100 | @as(u16, cpu.sp));
}

fn push16(value: u16) void {
    push(@intCast((value >> 8) & 0x00FF));
    push(@intCast(value & 0x00FF));
}

fn pull16() u16 {
    const lo = pull();
    const hi = pull();
    return (@as(u16, hi) << 8) | lo;
}

fn flag(mask: u8) bool {
    return (cpu.p & mask) != 0;
}

fn setFlag(mask: u8, value: bool) void {
    if (value) {
        cpu.p |= mask;
    } else {
        cpu.p &= ~mask;
    }
    cpu.p |= FLAG_U;
}

fn setZN(value: u8) void {
    setFlag(FLAG_Z, value == 0);
    setFlag(FLAG_N, (value & 0x80) != 0);
}

fn branch(condition: bool) void {
    const off: i8 = @bitCast(fetch());
    if (condition) cpu.pc = @bitCast(@as(i16, @bitCast(cpu.pc)) +% @as(i16, off));
}

fn lda(value: u8) void {
    cpu.a = value;
    setZN(cpu.a);
}

fn ldx(value: u8) void {
    cpu.x = value;
    setZN(cpu.x);
}

fn ldy(value: u8) void {
    cpu.y = value;
    setZN(cpu.y);
}

fn nopRead(addr: u16) void {
    _ = read(addr);
}

fn sta(addr: u16) void {
    write(addr, cpu.a);
}

fn stx(addr: u16) void {
    write(addr, cpu.x);
}

fn sty(addr: u16) void {
    write(addr, cpu.y);
}

fn ora(value: u8) void {
    cpu.a |= value;
    setZN(cpu.a);
}

fn andOp(value: u8) void {
    cpu.a &= value;
    setZN(cpu.a);
}

fn eor(value: u8) void {
    cpu.a ^= value;
    setZN(cpu.a);
}

fn adc(value: u8) void {
    if (flag(FLAG_D)) {
        adcDecimal(value);
        return;
    }
    const carry: u16 = if (flag(FLAG_C)) 1 else 0;
    const sum = @as(u16, cpu.a) + @as(u16, value) + carry;
    const result: u8 = @truncate(sum);
    setFlag(FLAG_C, sum > 0xFF);
    setFlag(FLAG_V, ((~(@as(u16, cpu.a) ^ @as(u16, value)) & (@as(u16, cpu.a) ^ result)) & 0x80) != 0);
    cpu.a = result;
    setZN(cpu.a);
}

fn sbc(value: u8) void {
    if (flag(FLAG_D)) {
        sbcDecimal(value);
        return;
    }
    adc(value ^ 0xFF);
}

fn adcDecimal(value: u8) void {
    const old_a = cpu.a;
    const carry_in: u8 = if (flag(FLAG_C)) 1 else 0;
    const binary_sum = @as(u16, old_a) + @as(u16, value) + carry_in;
    var lo = (old_a & 0x0F) + (value & 0x0F) + carry_in;
    var hi = (old_a >> 4) + (value >> 4);
    if (lo > 9) {
        lo += 6;
        hi += 1;
    }
    if (hi > 9) hi += 6;
    const result: u8 = ((hi & 0x0F) << 4) | (lo & 0x0F);
    cpu.a = result;
    setFlag(FLAG_C, hi > 0x0F);
    setFlag(FLAG_V, ((~(@as(u16, old_a) ^ @as(u16, value)) & (@as(u16, old_a) ^ binary_sum)) & 0x80) != 0);
    setZN(cpu.a);
}

fn sbcDecimal(value: u8) void {
    const old_a = cpu.a;
    const borrow: u8 = if (flag(FLAG_C)) 0 else 1;
    const binary_diff = @as(i16, old_a) - @as(i16, value) - @as(i16, borrow);
    var lo = @as(i16, old_a & 0x0F) - @as(i16, value & 0x0F) - @as(i16, borrow);
    var hi = @as(i16, old_a >> 4) - @as(i16, value >> 4);
    if (lo < 0) {
        lo -= 6;
        hi -= 1;
    }
    if (hi < 0) hi -= 6;
    const hi_nibble: u8 = @intCast(hi & 0x0F);
    const lo_nibble: u8 = @intCast(lo & 0x0F);
    const result: u8 = (hi_nibble << 4) | lo_nibble;
    cpu.a = result;
    setFlag(FLAG_C, binary_diff >= 0);
    setFlag(FLAG_V, (((@as(u16, old_a) ^ @as(u16, value)) & (@as(u16, old_a) ^ @as(u16, @intCast(binary_diff & 0x00FF)))) & 0x80) != 0);
    setZN(cpu.a);
}

fn cmp(left: u8, right: u8) void {
    const result = left -% right;
    setFlag(FLAG_C, left >= right);
    setZN(result);
}

fn bit(value: u8) void {
    setFlag(FLAG_Z, (cpu.a & value) == 0);
    setFlag(FLAG_V, (value & FLAG_V) != 0);
    setFlag(FLAG_N, (value & FLAG_N) != 0);
}

fn aslValue(value: u8) u8 {
    setFlag(FLAG_C, (value & 0x80) != 0);
    const result = value << 1;
    setZN(result);
    return result;
}

fn lsrValue(value: u8) u8 {
    setFlag(FLAG_C, (value & 0x01) != 0);
    const result = value >> 1;
    setZN(result);
    return result;
}

fn rolValue(value: u8) u8 {
    const carry: u8 = if (flag(FLAG_C)) 1 else 0;
    setFlag(FLAG_C, (value & 0x80) != 0);
    const result = (value << 1) | carry;
    setZN(result);
    return result;
}

fn rorValue(value: u8) u8 {
    const carry: u8 = if (flag(FLAG_C)) 0x80 else 0;
    setFlag(FLAG_C, (value & 0x01) != 0);
    const result = (value >> 1) | carry;
    setZN(result);
    return result;
}

fn aslMem(addr: u16) void {
    write(addr, aslValue(read(addr)));
}

fn lsrMem(addr: u16) void {
    write(addr, lsrValue(read(addr)));
}

fn rolMem(addr: u16) void {
    write(addr, rolValue(read(addr)));
}

fn rorMem(addr: u16) void {
    write(addr, rorValue(read(addr)));
}

fn incMem(addr: u16) void {
    const value = read(addr) +% 1;
    write(addr, value);
    setZN(value);
}

fn decMem(addr: u16) void {
    const value = read(addr) -% 1;
    write(addr, value);
    setZN(value);
}

fn jsr() void {
    const target = fetch16();
    push16(cpu.pc -% 1);
    cpu.pc = target;
}

fn rti() void {
    cpu.p = (pull() | FLAG_U) & ~FLAG_B;
    cpu.pc = pull16();
}
