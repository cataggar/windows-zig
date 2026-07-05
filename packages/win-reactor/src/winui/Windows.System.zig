const std = @import("std");
const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const BOOL = win_core.BOOL;
pub const IInspectable_Vtbl = win_core.IInspectable_Vtbl;

pub const DispatcherQueuePriority = enum(i32) {
    Low = -10,
    Normal = 0,
    High = 10,
    _,
};

pub const DispatcherQueueHandler = opaque {};

pub const DispatcherQueueTimer = extern struct {
    vtable: *const anyopaque,
};

pub const IDispatcherQueue_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    CreateTimer: *const fn (this: *const IDispatcherQueue, result: **DispatcherQueueTimer) callconv(.winapi) HRESULT,
    TryEnqueue: *const fn (this: *const IDispatcherQueue, p0: *DispatcherQueueHandler, result: *BOOL) callconv(.winapi) HRESULT,
    TryEnqueue_2: *const fn (this: *const IDispatcherQueue, p0: DispatcherQueuePriority, p1: *DispatcherQueueHandler, result: *BOOL) callconv(.winapi) HRESULT,
};

pub const IDispatcherQueue = extern struct {
    vtable: *const IDispatcherQueue_Vtbl,
    pub const Vtbl = IDispatcherQueue_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x603E88E4,
        .data2 = 0xA338,
        .data3 = 0x4FFE,
        .data4 = .{ 0xA4, 0x57, 0xA5, 0xCF, 0xB9, 0xCE, 0xB8, 0x99 },
    };

    pub fn QueryInterface(self: *const IDispatcherQueue, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IDispatcherQueue) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IDispatcherQueue) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn TryEnqueue_2(self: *const IDispatcherQueue, priority: DispatcherQueuePriority, handler: *DispatcherQueueHandler, result: *BOOL) callconv(.winapi) HRESULT {
        return self.vtable.TryEnqueue_2(self, priority, handler, result);
    }
};

pub const IDispatcherQueueStatics_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetForCurrentThread: *const fn (this: *const IDispatcherQueueStatics, result: *?*DispatcherQueue) callconv(.winapi) HRESULT,
};

pub const IDispatcherQueueStatics = extern struct {
    vtable: *const IDispatcherQueueStatics_Vtbl,
    pub const Vtbl = IDispatcherQueueStatics_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0xA96D83D7,
        .data2 = 0x9371,
        .data3 = 0x4517,
        .data4 = .{ 0x92, 0x45, 0xD0, 0x82, 0x4A, 0xC1, 0x2C, 0x74 },
    };

    pub fn QueryInterface(self: *const IDispatcherQueueStatics, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IDispatcherQueueStatics) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IDispatcherQueueStatics) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn GetForCurrentThread(self: *const IDispatcherQueueStatics, result: *?*DispatcherQueue) callconv(.winapi) HRESULT {
        return self.vtable.GetForCurrentThread(self, result);
    }
};

pub const IDispatcherQueueController_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_DispatcherQueue: *const fn (this: *const IDispatcherQueueController, result: *?*DispatcherQueue) callconv(.winapi) HRESULT,
    ShutdownQueueAsync: *const fn (this: *const IDispatcherQueueController, result: *?*anyopaque) callconv(.winapi) HRESULT,
};

pub const IDispatcherQueueController = extern struct {
    vtable: *const IDispatcherQueueController_Vtbl,
    pub const Vtbl = IDispatcherQueueController_Vtbl;
    pub const IID: GUID = .{
        .data1 = 0x22F34E66,
        .data2 = 0x50DB,
        .data3 = 0x4E36,
        .data4 = .{ 0xA9, 0x8D, 0x61, 0xC0, 0x1B, 0x38, 0x4D, 0x20 },
    };

    pub fn QueryInterface(self: *const IDispatcherQueueController, iid: *const GUID, interface: *?*anyopaque) callconv(.winapi) HRESULT {
        return self.vtable.base.base.QueryInterface(@ptrCast(@constCast(self)), iid, interface);
    }

    pub fn AddRef(self: *const IDispatcherQueueController) callconv(.winapi) u32 {
        return self.vtable.base.base.AddRef(@ptrCast(@constCast(self)));
    }

    pub fn Release(self: *const IDispatcherQueueController) callconv(.winapi) u32 {
        return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
    }

    pub fn get_DispatcherQueue(self: *const IDispatcherQueueController, result: *?*DispatcherQueue) callconv(.winapi) HRESULT {
        return self.vtable.get_DispatcherQueue(self, result);
    }
};

pub const DispatcherQueue = extern struct {
    vtable: *const IDispatcherQueue_Vtbl,
    pub const NAME: []const u8 = "Windows.System.DispatcherQueue";
    pub const NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(NAME).*;
    pub const Statics = IDispatcherQueueStatics;

    pub fn statics() !win_core.Com(Statics.Vtbl) {
        return win_core.activationFactory(Statics.Vtbl, &Statics.IID, &NAME_W);
    }
};
