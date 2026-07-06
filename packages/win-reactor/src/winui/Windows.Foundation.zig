const win_core = @import("win-core");

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
pub const BOOL = win_core.BOOL;

pub const EventRegistrationToken = extern struct {
    Value: i64,
};

pub const Point = extern struct {
    X: f32 = 0,
    Y: f32 = 0,
};
