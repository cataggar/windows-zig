const win_core = @import("win-core");

pub const EventRegistrationToken = extern struct {
    Value: i64,
};

pub const GUID = win_core.GUID;
pub const HRESULT = win_core.HRESULT;
