const r4os = @import("r4os");
const sid = @import("engine.zig");

var engine_stops: u64 = 0;
var engine_plays: u64 = 0;
var engine_last_result: i32 = 0;
var engine: r4os.abi.SynthEngine = .{};

comptime {
    asm (r4os.r4dev.driverEntriesAsm("sid_init", "sid_shutdown"));
}

export fn sid_init(api: *const r4os.r4dev.DriverApi) callconv(.c) i32 {
    var ctx = r4os.r4dev.DriverContext.init(api);
    ctx.logInfo("SID synth engine init");
    engine = .{
        .flags = r4os.abi.synth_engine_flag_sid,
        .stop = sidStop,
        .status = sidStatus,
        .sid_acquire = sidAcquire,
        .sid_release = sidRelease,
        .sid_set_model = sidSetModel,
        .sid_write_register = sidWriteRegister,
        .sid_load_data = sidLoadData,
        .sid_init = sidInit,
        .sid_play_frame = sidPlayFrame,
        .sid_render_pcm = sidRenderPcm,
    };
    if (ctx.registerSynthEngineEx("SID", &engine) != 0) return -1;
    return 0;
}

export fn sid_shutdown() callconv(.c) i32 {
    return 0;
}

fn sidStop(context: ?*anyopaque) callconv(.c) i32 {
    _ = context;
    sid.stopRuntime();
    engine_stops +%= 1;
    engine_last_result = 0;
    return 0;
}

fn sidAcquire(context: ?*anyopaque) callconv(.c) i32 {
    _ = context;
    engine_last_result = 0;
    return 1;
}

fn sidRelease(context: ?*anyopaque, handle: u32) callconv(.c) i32 {
    _ = context;
    _ = handle;
    engine_last_result = 0;
    return 0;
}

fn sidSetModel(context: ?*anyopaque, model: u32) callconv(.c) i32 {
    _ = context;
    switch (model) {
        r4os.abi.audio_sid_model_6581 => sid.configureModel("6581"),
        r4os.abi.audio_sid_model_8580 => sid.configureModel("8580"),
        else => return -1,
    }
    engine_last_result = 0;
    return 0;
}

fn sidWriteRegister(context: ?*anyopaque, handle: u32, register: u32, value: u32) callconv(.c) i32 {
    _ = context;
    if (handle != 1) return -1;
    engine_last_result = sid.writeRegister(@intCast(register & 0xFF), @intCast(value & 0xFF));
    return engine_last_result;
}

fn sidLoadData(context: ?*anyopaque, handle: u32, offset: u32, data: [*]const u8, len: u32) callconv(.c) i32 {
    _ = context;
    if (handle != 1) return -1;
    if (len == 0 or len > 65_536) return -2;
    const load_addr: u16 = @intCast(offset & 0xFFFF);
    const ok = sid.loadSidData(load_addr, data[0..len]);
    engine_last_result = if (ok) 0 else -3;
    return engine_last_result;
}

fn sidInit(context: ?*anyopaque, handle: u32, tune: u32, subtune: u32) callconv(.c) i32 {
    _ = context;
    if (handle != 1) return -1;
    const ok = sid.initSid(@intCast(tune & 0xFFFF), @intCast(subtune & 0xFFFF), 20_000);
    engine_last_result = if (ok) 0 else -2;
    return engine_last_result;
}

fn sidPlayFrame(context: ?*anyopaque, handle: u32, frames: u32, flags: u32) callconv(.c) i32 {
    _ = context;
    if (handle != 1) return -1;
    const ok = sid.playFrame(@intCast(frames & 0xFFFF), @intCast(flags & 0xFFFF), 20_000);
    engine_plays +%= 1;
    engine_last_result = if (ok) 0 else -2;
    return engine_last_result;
}

fn sidRenderPcm(context: ?*anyopaque, handle: u32, out: [*]u8, len: u32) callconv(.c) i32 {
    _ = context;
    if (handle != 1) return -1;
    if (len < sid.RENDER_BYTES) return -2;
    _ = sid.renderBlock(out[0..sid.RENDER_BYTES]);
    engine_last_result = 0;
    return sid.RENDER_BYTES;
}

fn sidStatus(context: ?*anyopaque, out: *r4os.abi.SynthEngineStatus) callconv(.c) i32 {
    _ = context;
    out.* = .{
        .active = 1,
        .renders = engine_plays,
        .stops = engine_stops,
        .last_result = engine_last_result,
    };
    return 0;
}
