//! `win-numerics` — Windows numerics math value types.

const std = @import("std");

pub const Vector2 = extern struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub const zero: Self = .{ .x = 0.0, .y = 0.0 };
    pub const one: Self = .{ .x = 1.0, .y = 1.0 };
    pub const unitX: Self = .{ .x = 1.0, .y = 0.0 };
    pub const unitY: Self = .{ .x = 0.0, .y = 1.0 };

    pub fn init(x: f32, y: f32) Self {
        return .{ .x = x, .y = y };
    }

    pub fn dot(self: Self, rhs: Self) f32 {
        return self.x * rhs.x + self.y * rhs.y;
    }

    pub fn lengthSquared(self: Self) f32 {
        return self.dot(self);
    }

    pub fn length(self: Self) f32 {
        return @sqrt(self.lengthSquared());
    }

    pub fn distance(self: Self, value: Self) f32 {
        return self.sub(value).length();
    }

    pub fn distanceSquared(self: Self, value: Self) f32 {
        return self.sub(value).lengthSquared();
    }

    pub fn normalize(self: Self) Self {
        return self.divScalar(self.length());
    }

    pub fn negate(self: Self) Self {
        return .{ .x = -self.x, .y = -self.y };
    }

    pub fn add(self: Self, rhs: Self) Self {
        return .{
            .x = self.x + rhs.x,
            .y = self.y + rhs.y,
        };
    }

    pub fn sub(self: Self, rhs: Self) Self {
        return .{
            .x = self.x - rhs.x,
            .y = self.y - rhs.y,
        };
    }

    pub fn div(self: Self, rhs: Self) Self {
        return .{
            .x = self.x / rhs.x,
            .y = self.y / rhs.y,
        };
    }

    pub fn divScalar(self: Self, rhs: f32) Self {
        return .{
            .x = self.x / rhs,
            .y = self.y / rhs,
        };
    }

    pub fn mul(self: Self, rhs: Self) Self {
        return .{
            .x = self.x * rhs.x,
            .y = self.y * rhs.y,
        };
    }

    pub fn scale(self: Self, rhs: f32) Self {
        return .{
            .x = self.x * rhs,
            .y = self.y * rhs,
        };
    }
};

pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    pub const zero: Self = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    pub const one: Self = .{ .x = 1.0, .y = 1.0, .z = 1.0 };
    pub const unitX: Self = .{ .x = 1.0, .y = 0.0, .z = 0.0 };
    pub const unitY: Self = .{ .x = 0.0, .y = 1.0, .z = 0.0 };
    pub const unitZ: Self = .{ .x = 0.0, .y = 0.0, .z = 1.0 };

    pub fn init(x: f32, y: f32, z: f32) Self {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn dot(self: Self, rhs: Self) f32 {
        return self.x * rhs.x + self.y * rhs.y + self.z * rhs.z;
    }

    pub fn lengthSquared(self: Self) f32 {
        return self.dot(self);
    }

    pub fn length(self: Self) f32 {
        return @sqrt(self.lengthSquared());
    }

    pub fn distance(self: Self, value: Self) f32 {
        return self.sub(value).length();
    }

    pub fn distanceSquared(self: Self, value: Self) f32 {
        return self.sub(value).lengthSquared();
    }

    pub fn normalize(self: Self) Self {
        return self.divScalar(self.length());
    }

    pub fn cross(self: Self, rhs: Self) Self {
        return .{
            .x = self.y * rhs.z - self.z * rhs.y,
            .y = self.z * rhs.x - self.x * rhs.z,
            .z = self.x * rhs.y - self.y * rhs.x,
        };
    }

    pub fn negate(self: Self) Self {
        return .{ .x = -self.x, .y = -self.y, .z = -self.z };
    }

    pub fn add(self: Self, rhs: Self) Self {
        return .{
            .x = self.x + rhs.x,
            .y = self.y + rhs.y,
            .z = self.z + rhs.z,
        };
    }

    pub fn sub(self: Self, rhs: Self) Self {
        return .{
            .x = self.x - rhs.x,
            .y = self.y - rhs.y,
            .z = self.z - rhs.z,
        };
    }

    pub fn div(self: Self, rhs: Self) Self {
        return .{
            .x = self.x / rhs.x,
            .y = self.y / rhs.y,
            .z = self.z / rhs.z,
        };
    }

    pub fn divScalar(self: Self, rhs: f32) Self {
        return .{
            .x = self.x / rhs,
            .y = self.y / rhs,
            .z = self.z / rhs,
        };
    }

    pub fn mul(self: Self, rhs: Self) Self {
        return .{
            .x = self.x * rhs.x,
            .y = self.y * rhs.y,
            .z = self.z * rhs.z,
        };
    }

    pub fn scale(self: Self, rhs: f32) Self {
        return .{
            .x = self.x * rhs,
            .y = self.y * rhs,
            .z = self.z * rhs,
        };
    }
};

pub const Vector4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    const Self = @This();

    pub const zero: Self = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };
    pub const one: Self = .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    pub const unitX: Self = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 0.0 };
    pub const unitY: Self = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 };
    pub const unitZ: Self = .{ .x = 0.0, .y = 0.0, .z = 1.0, .w = 0.0 };
    pub const unitW: Self = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

    pub fn init(x: f32, y: f32, z: f32, w: f32) Self {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn dot(self: Self, rhs: Self) f32 {
        return self.x * rhs.x + self.y * rhs.y + self.z * rhs.z + self.w * rhs.w;
    }

    pub fn lengthSquared(self: Self) f32 {
        return self.dot(self);
    }

    pub fn length(self: Self) f32 {
        return @sqrt(self.lengthSquared());
    }

    pub fn distance(self: Self, value: Self) f32 {
        return self.sub(value).length();
    }

    pub fn distanceSquared(self: Self, value: Self) f32 {
        return self.sub(value).lengthSquared();
    }

    pub fn normalize(self: Self) Self {
        return self.divScalar(self.length());
    }

    pub fn negate(self: Self) Self {
        return .{ .x = -self.x, .y = -self.y, .z = -self.z, .w = -self.w };
    }

    pub fn add(self: Self, rhs: Self) Self {
        return .{
            .x = self.x + rhs.x,
            .y = self.y + rhs.y,
            .z = self.z + rhs.z,
            .w = self.w + rhs.w,
        };
    }

    pub fn sub(self: Self, rhs: Self) Self {
        return .{
            .x = self.x - rhs.x,
            .y = self.y - rhs.y,
            .z = self.z - rhs.z,
            .w = self.w - rhs.w,
        };
    }

    pub fn div(self: Self, rhs: Self) Self {
        return .{
            .x = self.x / rhs.x,
            .y = self.y / rhs.y,
            .z = self.z / rhs.z,
            .w = self.w / rhs.w,
        };
    }

    pub fn divScalar(self: Self, rhs: f32) Self {
        return .{
            .x = self.x / rhs,
            .y = self.y / rhs,
            .z = self.z / rhs,
            .w = self.w / rhs,
        };
    }

    pub fn mul(self: Self, rhs: Self) Self {
        return .{
            .x = self.x * rhs.x,
            .y = self.y * rhs.y,
            .z = self.z * rhs.z,
            .w = self.w * rhs.w,
        };
    }

    pub fn scale(self: Self, rhs: f32) Self {
        return .{
            .x = self.x * rhs,
            .y = self.y * rhs,
            .z = self.z * rhs,
            .w = self.w * rhs,
        };
    }
};

pub const Matrix3x2 = extern struct {
    m11: f32,
    m12: f32,
    m21: f32,
    m22: f32,
    m31: f32,
    m32: f32,

    const Self = @This();

    pub const identity: Self = .{
        .m11 = 1.0,
        .m12 = 0.0,
        .m21 = 0.0,
        .m22 = 1.0,
        .m31 = 0.0,
        .m32 = 0.0,
    };

    pub fn init(m11: f32, m12: f32, m21: f32, m22: f32, m31: f32, m32: f32) Self {
        return .{
            .m11 = m11,
            .m12 = m12,
            .m21 = m21,
            .m22 = m22,
            .m31 = m31,
            .m32 = m32,
        };
    }

    pub fn translation(x: f32, y: f32) Self {
        return .{
            .m11 = 1.0,
            .m12 = 0.0,
            .m21 = 0.0,
            .m22 = 1.0,
            .m31 = x,
            .m32 = y,
        };
    }

    pub fn rotation(angle: f32) Self {
        return rotationAround(angle, Vector2.zero);
    }

    pub fn rotationAround(angle: f32, center: Vector2) Self {
        const trig = sinCos(angle);
        return .{
            .m11 = trig.cos,
            .m12 = trig.sin,
            .m21 = -trig.sin,
            .m22 = trig.cos,
            .m31 = center.x * (1.0 - trig.cos) + center.y * trig.sin,
            .m32 = center.y * (1.0 - trig.cos) - center.x * trig.sin,
        };
    }

    pub fn scale(scale_x: f32, scale_y: f32) Self {
        return scaleAround(scale_x, scale_y, Vector2.zero);
    }

    pub fn scaleAround(scale_x: f32, scale_y: f32, center: Vector2) Self {
        return .{
            .m11 = scale_x,
            .m12 = 0.0,
            .m21 = 0.0,
            .m22 = scale_y,
            .m31 = center.x - scale_x * center.x,
            .m32 = center.y - scale_y * center.y,
        };
    }

    pub fn skew(angle_x: f32, angle_y: f32) Self {
        return skewAround(angle_x, angle_y, Vector2.zero);
    }

    pub fn skewAround(angle_x: f32, angle_y: f32, center: Vector2) Self {
        const tan_x = @tan(degreesToRadians(angle_x));
        const tan_y = @tan(degreesToRadians(angle_y));
        return .{
            .m11 = 1.0,
            .m12 = tan_y,
            .m21 = tan_x,
            .m22 = 1.0,
            .m31 = -center.y * tan_x,
            .m32 = -center.x * tan_y,
        };
    }

    pub fn add(self: Self, rhs: Self) Self {
        return .{
            .m11 = self.m11 + rhs.m11,
            .m12 = self.m12 + rhs.m12,
            .m21 = self.m21 + rhs.m21,
            .m22 = self.m22 + rhs.m22,
            .m31 = self.m31 + rhs.m31,
            .m32 = self.m32 + rhs.m32,
        };
    }

    pub fn sub(self: Self, rhs: Self) Self {
        return .{
            .m11 = self.m11 - rhs.m11,
            .m12 = self.m12 - rhs.m12,
            .m21 = self.m21 - rhs.m21,
            .m22 = self.m22 - rhs.m22,
            .m31 = self.m31 - rhs.m31,
            .m32 = self.m32 - rhs.m32,
        };
    }

    pub fn mul(self: Self, rhs: Self) Self {
        return .{
            .m11 = self.m11 * rhs.m11 + self.m12 * rhs.m21,
            .m12 = self.m11 * rhs.m12 + self.m12 * rhs.m22,
            .m21 = self.m21 * rhs.m11 + self.m22 * rhs.m21,
            .m22 = self.m21 * rhs.m12 + self.m22 * rhs.m22,
            .m31 = self.m31 * rhs.m11 + self.m32 * rhs.m21 + rhs.m31,
            .m32 = self.m31 * rhs.m12 + self.m32 * rhs.m22 + rhs.m32,
        };
    }

    pub fn mulScalar(self: Self, rhs: f32) Self {
        return .{
            .m11 = self.m11 * rhs,
            .m12 = self.m12 * rhs,
            .m21 = self.m21 * rhs,
            .m22 = self.m22 * rhs,
            .m31 = self.m31 * rhs,
            .m32 = self.m32 * rhs,
        };
    }
};

pub const Matrix4x4 = extern struct {
    m11: f32,
    m12: f32,
    m13: f32,
    m14: f32,
    m21: f32,
    m22: f32,
    m23: f32,
    m24: f32,
    m31: f32,
    m32: f32,
    m33: f32,
    m34: f32,
    m41: f32,
    m42: f32,
    m43: f32,
    m44: f32,

    const Self = @This();

    pub fn init(
        m11: f32,
        m12: f32,
        m13: f32,
        m14: f32,
        m21: f32,
        m22: f32,
        m23: f32,
        m24: f32,
        m31: f32,
        m32: f32,
        m33: f32,
        m34: f32,
        m41: f32,
        m42: f32,
        m43: f32,
        m44: f32,
    ) Self {
        return .{
            .m11 = m11,
            .m12 = m12,
            .m13 = m13,
            .m14 = m14,
            .m21 = m21,
            .m22 = m22,
            .m23 = m23,
            .m24 = m24,
            .m31 = m31,
            .m32 = m32,
            .m33 = m33,
            .m34 = m34,
            .m41 = m41,
            .m42 = m42,
            .m43 = m43,
            .m44 = m44,
        };
    }

    pub fn translation(x: f32, y: f32, z: f32) Self {
        return .{
            .m11 = 1.0,
            .m12 = 0.0,
            .m13 = 0.0,
            .m14 = 0.0,
            .m21 = 0.0,
            .m22 = 1.0,
            .m23 = 0.0,
            .m24 = 0.0,
            .m31 = 0.0,
            .m32 = 0.0,
            .m33 = 1.0,
            .m34 = 0.0,
            .m41 = x,
            .m42 = y,
            .m43 = z,
            .m44 = 1.0,
        };
    }

    pub fn rotationY(degree: f32) Self {
        const trig = sinCos(degree);
        return .{
            .m11 = trig.cos,
            .m12 = 0.0,
            .m13 = -trig.sin,
            .m14 = 0.0,
            .m21 = 0.0,
            .m22 = 1.0,
            .m23 = 0.0,
            .m24 = 0.0,
            .m31 = trig.sin,
            .m32 = 0.0,
            .m33 = trig.cos,
            .m34 = 0.0,
            .m41 = 0.0,
            .m42 = 0.0,
            .m43 = 0.0,
            .m44 = 1.0,
        };
    }

    pub fn perspectiveProjection(depth: f32) Self {
        const projection: f32 = if (depth > 0.0) -1.0 / depth else 0.0;
        return .{
            .m11 = 1.0,
            .m12 = 0.0,
            .m13 = 0.0,
            .m14 = 0.0,
            .m21 = 0.0,
            .m22 = 1.0,
            .m23 = 0.0,
            .m24 = 0.0,
            .m31 = 0.0,
            .m32 = 0.0,
            .m33 = 1.0,
            .m34 = projection,
            .m41 = 0.0,
            .m42 = 0.0,
            .m43 = 0.0,
            .m44 = 1.0,
        };
    }

    pub fn add(self: Self, rhs: Self) Self {
        return .{
            .m11 = self.m11 + rhs.m11,
            .m12 = self.m12 + rhs.m12,
            .m13 = self.m13 + rhs.m13,
            .m14 = self.m14 + rhs.m14,
            .m21 = self.m21 + rhs.m21,
            .m22 = self.m22 + rhs.m22,
            .m23 = self.m23 + rhs.m23,
            .m24 = self.m24 + rhs.m24,
            .m31 = self.m31 + rhs.m31,
            .m32 = self.m32 + rhs.m32,
            .m33 = self.m33 + rhs.m33,
            .m34 = self.m34 + rhs.m34,
            .m41 = self.m41 + rhs.m41,
            .m42 = self.m42 + rhs.m42,
            .m43 = self.m43 + rhs.m43,
            .m44 = self.m44 + rhs.m44,
        };
    }

    pub fn sub(self: Self, rhs: Self) Self {
        return .{
            .m11 = self.m11 - rhs.m11,
            .m12 = self.m12 - rhs.m12,
            .m13 = self.m13 - rhs.m13,
            .m14 = self.m14 - rhs.m14,
            .m21 = self.m21 - rhs.m21,
            .m22 = self.m22 - rhs.m22,
            .m23 = self.m23 - rhs.m23,
            .m24 = self.m24 - rhs.m24,
            .m31 = self.m31 - rhs.m31,
            .m32 = self.m32 - rhs.m32,
            .m33 = self.m33 - rhs.m33,
            .m34 = self.m34 - rhs.m34,
            .m41 = self.m41 - rhs.m41,
            .m42 = self.m42 - rhs.m42,
            .m43 = self.m43 - rhs.m43,
            .m44 = self.m44 - rhs.m44,
        };
    }

    pub fn mul(self: Self, rhs: Self) Self {
        return .{
            .m11 = self.m11 * rhs.m11 + self.m12 * rhs.m21 + self.m13 * rhs.m31 + self.m14 * rhs.m41,
            .m12 = self.m11 * rhs.m12 + self.m12 * rhs.m22 + self.m13 * rhs.m32 + self.m14 * rhs.m42,
            .m13 = self.m11 * rhs.m13 + self.m12 * rhs.m23 + self.m13 * rhs.m33 + self.m14 * rhs.m43,
            .m14 = self.m11 * rhs.m14 + self.m12 * rhs.m24 + self.m13 * rhs.m34 + self.m14 * rhs.m44,
            .m21 = self.m21 * rhs.m11 + self.m22 * rhs.m21 + self.m23 * rhs.m31 + self.m24 * rhs.m41,
            .m22 = self.m21 * rhs.m12 + self.m22 * rhs.m22 + self.m23 * rhs.m32 + self.m24 * rhs.m42,
            .m23 = self.m21 * rhs.m13 + self.m22 * rhs.m23 + self.m23 * rhs.m33 + self.m24 * rhs.m43,
            .m24 = self.m21 * rhs.m14 + self.m22 * rhs.m24 + self.m23 * rhs.m34 + self.m24 * rhs.m44,
            .m31 = self.m31 * rhs.m11 + self.m32 * rhs.m21 + self.m33 * rhs.m31 + self.m34 * rhs.m41,
            .m32 = self.m31 * rhs.m12 + self.m32 * rhs.m22 + self.m33 * rhs.m32 + self.m34 * rhs.m42,
            .m33 = self.m31 * rhs.m13 + self.m32 * rhs.m23 + self.m33 * rhs.m33 + self.m34 * rhs.m43,
            .m34 = self.m31 * rhs.m14 + self.m32 * rhs.m24 + self.m33 * rhs.m34 + self.m34 * rhs.m44,
            .m41 = self.m41 * rhs.m11 + self.m42 * rhs.m21 + self.m43 * rhs.m31 + self.m44 * rhs.m41,
            .m42 = self.m41 * rhs.m12 + self.m42 * rhs.m22 + self.m43 * rhs.m32 + self.m44 * rhs.m42,
            .m43 = self.m41 * rhs.m13 + self.m42 * rhs.m23 + self.m43 * rhs.m33 + self.m44 * rhs.m43,
            .m44 = self.m41 * rhs.m14 + self.m42 * rhs.m24 + self.m43 * rhs.m34 + self.m44 * rhs.m44,
        };
    }

    pub fn mulScalar(self: Self, rhs: f32) Self {
        return .{
            .m11 = self.m11 * rhs,
            .m12 = self.m12 * rhs,
            .m13 = self.m13 * rhs,
            .m14 = self.m14 * rhs,
            .m21 = self.m21 * rhs,
            .m22 = self.m22 * rhs,
            .m23 = self.m23 * rhs,
            .m24 = self.m24 * rhs,
            .m31 = self.m31 * rhs,
            .m32 = self.m32 * rhs,
            .m33 = self.m33 * rhs,
            .m34 = self.m34 * rhs,
            .m41 = self.m41 * rhs,
            .m42 = self.m42 * rhs,
            .m43 = self.m43 * rhs,
            .m44 = self.m44 * rhs,
        };
    }
};

fn degreesToRadians(angle: f32) f32 {
    return angle * (@as(f32, std.math.pi) / 180.0);
}

fn sinCos(angle: f32) struct { sin: f32, cos: f32 } {
    const radians = degreesToRadians(angle);
    return .{
        .sin = @sin(radians),
        .cos = @cos(radians),
    };
}

fn expectApproxEq(expected: f32, actual: f32) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.0001);
}

fn expectVector2(expected: Vector2, actual: Vector2) !void {
    try expectApproxEq(expected.x, actual.x);
    try expectApproxEq(expected.y, actual.y);
}

fn expectVector3(expected: Vector3, actual: Vector3) !void {
    try expectApproxEq(expected.x, actual.x);
    try expectApproxEq(expected.y, actual.y);
    try expectApproxEq(expected.z, actual.z);
}

fn expectVector4(expected: Vector4, actual: Vector4) !void {
    try expectApproxEq(expected.x, actual.x);
    try expectApproxEq(expected.y, actual.y);
    try expectApproxEq(expected.z, actual.z);
    try expectApproxEq(expected.w, actual.w);
}

fn expectMatrix3x2(expected: Matrix3x2, actual: Matrix3x2) !void {
    try expectApproxEq(expected.m11, actual.m11);
    try expectApproxEq(expected.m12, actual.m12);
    try expectApproxEq(expected.m21, actual.m21);
    try expectApproxEq(expected.m22, actual.m22);
    try expectApproxEq(expected.m31, actual.m31);
    try expectApproxEq(expected.m32, actual.m32);
}

fn expectMatrix4x4(expected: Matrix4x4, actual: Matrix4x4) !void {
    try expectApproxEq(expected.m11, actual.m11);
    try expectApproxEq(expected.m12, actual.m12);
    try expectApproxEq(expected.m13, actual.m13);
    try expectApproxEq(expected.m14, actual.m14);
    try expectApproxEq(expected.m21, actual.m21);
    try expectApproxEq(expected.m22, actual.m22);
    try expectApproxEq(expected.m23, actual.m23);
    try expectApproxEq(expected.m24, actual.m24);
    try expectApproxEq(expected.m31, actual.m31);
    try expectApproxEq(expected.m32, actual.m32);
    try expectApproxEq(expected.m33, actual.m33);
    try expectApproxEq(expected.m34, actual.m34);
    try expectApproxEq(expected.m41, actual.m41);
    try expectApproxEq(expected.m42, actual.m42);
    try expectApproxEq(expected.m43, actual.m43);
    try expectApproxEq(expected.m44, actual.m44);
}

test "Vector2 arithmetic matches windows-numerics" {
    const v = Vector2.init(3.0, 4.0);
    try expectVector2(Vector2.zero, Vector2.zero);
    try expectVector2(Vector2.one, Vector2.one);
    try expectVector2(Vector2.unitX, Vector2.unitX);
    try expectVector2(Vector2.unitY, Vector2.unitY);
    try expectApproxEq(25.0, v.lengthSquared());
    try expectApproxEq(5.0, v.length());
    try expectApproxEq(5.0, v.distance(Vector2.zero));
    try expectApproxEq(25.0, v.distanceSquared(Vector2.zero));
    try expectApproxEq(7.0, v.dot(Vector2.init(1.0, 1.0)));
    try expectVector2(Vector2.init(0.6, 0.8), v.normalize());
    try expectVector2(Vector2.init(-3.0, -4.0), v.negate());
    try expectVector2(Vector2.init(5.0, 12.0), v.add(Vector2.init(2.0, 8.0)));
    try expectVector2(Vector2.init(1.0, -4.0), v.sub(Vector2.init(2.0, 8.0)));
    try expectVector2(Vector2.init(6.0, 32.0), v.mul(Vector2.init(2.0, 8.0)));
    try expectVector2(Vector2.init(1.5, 0.5), v.div(Vector2.init(2.0, 8.0)));
    try expectVector2(Vector2.init(6.0, 8.0), v.scale(2.0));
    try expectVector2(Vector2.init(1.5, 2.0), v.divScalar(2.0));
}

test "Vector3 arithmetic matches windows-numerics" {
    const v = Vector3.init(1.0, 2.0, 3.0);
    const w = Vector3.init(4.0, 5.0, 6.0);
    try expectVector3(Vector3.zero, Vector3.zero);
    try expectVector3(Vector3.one, Vector3.one);
    try expectVector3(Vector3.unitX, Vector3.unitX);
    try expectVector3(Vector3.unitY, Vector3.unitY);
    try expectVector3(Vector3.unitZ, Vector3.unitZ);
    try expectApproxEq(32.0, v.dot(w));
    try expectApproxEq(14.0, v.lengthSquared());
    try expectApproxEq(@sqrt(@as(f32, 14.0)), v.length());
    try expectApproxEq(@sqrt(@as(f32, 27.0)), v.distance(w));
    try expectApproxEq(27.0, v.distanceSquared(w));
    try expectVector3(Vector3.init(-3.0, 6.0, -3.0), v.cross(w));
    try expectVector3(Vector3.init(1.0 / @sqrt(@as(f32, 14.0)), 2.0 / @sqrt(@as(f32, 14.0)), 3.0 / @sqrt(@as(f32, 14.0))), v.normalize());
    try expectVector3(Vector3.init(-1.0, -2.0, -3.0), v.negate());
    try expectVector3(Vector3.init(5.0, 7.0, 9.0), v.add(w));
    try expectVector3(Vector3.init(-3.0, -3.0, -3.0), v.sub(w));
    try expectVector3(Vector3.init(4.0, 10.0, 18.0), v.mul(w));
    try expectVector3(Vector3.init(0.25, 0.4, 0.5), v.div(w));
    try expectVector3(Vector3.init(2.0, 4.0, 6.0), v.scale(2.0));
    try expectVector3(Vector3.init(0.5, 1.0, 1.5), v.divScalar(2.0));
}

test "Vector4 arithmetic matches windows-numerics" {
    const v = Vector4.init(1.0, 2.0, 3.0, 4.0);
    const w = Vector4.init(5.0, 6.0, 7.0, 8.0);
    try expectVector4(Vector4.zero, Vector4.zero);
    try expectVector4(Vector4.one, Vector4.one);
    try expectVector4(Vector4.unitX, Vector4.unitX);
    try expectVector4(Vector4.unitY, Vector4.unitY);
    try expectVector4(Vector4.unitZ, Vector4.unitZ);
    try expectVector4(Vector4.unitW, Vector4.unitW);
    try expectApproxEq(70.0, v.dot(w));
    try expectApproxEq(30.0, v.lengthSquared());
    try expectApproxEq(@sqrt(@as(f32, 30.0)), v.length());
    try expectApproxEq(@sqrt(@as(f32, 64.0)), v.distance(w));
    try expectApproxEq(64.0, v.distanceSquared(w));
    try expectVector4(
        Vector4.init(
            1.0 / @sqrt(@as(f32, 30.0)),
            2.0 / @sqrt(@as(f32, 30.0)),
            3.0 / @sqrt(@as(f32, 30.0)),
            4.0 / @sqrt(@as(f32, 30.0)),
        ),
        v.normalize(),
    );
    try expectVector4(Vector4.init(-1.0, -2.0, -3.0, -4.0), v.negate());
    try expectVector4(Vector4.init(6.0, 8.0, 10.0, 12.0), v.add(w));
    try expectVector4(Vector4.init(-4.0, -4.0, -4.0, -4.0), v.sub(w));
    try expectVector4(Vector4.init(5.0, 12.0, 21.0, 32.0), v.mul(w));
    try expectVector4(Vector4.init(0.2, 2.0 / 6.0, 3.0 / 7.0, 0.5), v.div(w));
    try expectVector4(Vector4.init(2.0, 4.0, 6.0, 8.0), v.scale(2.0));
    try expectVector4(Vector4.init(0.5, 1.0, 1.5, 2.0), v.divScalar(2.0));
}

test "Matrix3x2 arithmetic matches windows-numerics" {
    try expectMatrix3x2(
        Matrix3x2.init(1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
        Matrix3x2.identity,
    );
    try expectMatrix3x2(
        Matrix3x2.init(1.0, 0.0, 0.0, 1.0, 10.0, 20.0),
        Matrix3x2.translation(10.0, 20.0),
    );
    try expectMatrix3x2(
        Matrix3x2.init(0.0, 1.0, -1.0, 0.0, 0.0, 0.0),
        Matrix3x2.rotation(90.0),
    );
    try expectMatrix3x2(
        Matrix3x2.init(0.0, 1.0, -1.0, 0.0, 5.0, 1.0),
        Matrix3x2.rotationAround(90.0, Vector2.init(2.0, 3.0)),
    );
    try expectMatrix3x2(
        Matrix3x2.init(2.0, 0.0, 0.0, 3.0, 0.0, 0.0),
        Matrix3x2.scale(2.0, 3.0),
    );
    try expectMatrix3x2(
        Matrix3x2.init(2.0, 0.0, 0.0, 3.0, -4.0, -10.0),
        Matrix3x2.scaleAround(2.0, 3.0, Vector2.init(4.0, 5.0)),
    );
    try expectMatrix3x2(
        Matrix3x2.init(1.0, 1.0, 0.0, 1.0, 0.0, 0.0),
        Matrix3x2.skew(0.0, 45.0),
    );
    try expectMatrix3x2(
        Matrix3x2.init(1.0, 0.0, 1.0, 1.0, -5.0, 0.0),
        Matrix3x2.skewAround(45.0, 0.0, Vector2.init(0.0, 5.0)),
    );

    const a = Matrix3x2.translation(5.0, 7.0);
    const b = Matrix3x2.scale(2.0, 3.0);
    try expectMatrix3x2(
        Matrix3x2.init(3.0, 0.0, 0.0, 4.0, 5.0, 7.0),
        a.add(b),
    );
    try expectMatrix3x2(
        Matrix3x2.init(-1.0, 0.0, 0.0, -2.0, 5.0, 7.0),
        a.sub(b),
    );
    try expectMatrix3x2(
        Matrix3x2.init(2.0, 0.0, 0.0, 3.0, 10.0, 21.0),
        a.mul(b),
    );
    try expectMatrix3x2(
        Matrix3x2.init(2.5, 0.0, 0.0, 2.5, 12.5, 17.5),
        a.mulScalar(2.5),
    );
}

test "Matrix4x4 arithmetic matches windows-numerics" {
    try expectMatrix4x4(
        Matrix4x4.translation(1.0, 2.0, 3.0),
        Matrix4x4.init(
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            1.0,
            2.0,
            3.0,
            1.0,
        ),
    );
    try expectMatrix4x4(
        Matrix4x4.init(
            0.0,
            0.0,
            -1.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        ),
        Matrix4x4.rotationY(90.0),
    );
    try expectMatrix4x4(
        Matrix4x4.init(
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            -0.5,
            0.0,
            0.0,
            0.0,
            1.0,
        ),
        Matrix4x4.perspectiveProjection(2.0),
    );
    try expectMatrix4x4(
        Matrix4x4.init(
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        ),
        Matrix4x4.perspectiveProjection(0.0),
    );

    const a = Matrix4x4.translation(1.0, 2.0, 3.0);
    const b = Matrix4x4.translation(4.0, 5.0, 6.0);
    try expectMatrix4x4(
        Matrix4x4.init(
            2.0,
            0.0,
            0.0,
            0.0,
            0.0,
            2.0,
            0.0,
            0.0,
            0.0,
            0.0,
            2.0,
            0.0,
            5.0,
            7.0,
            9.0,
            2.0,
        ),
        a.add(b),
    );
    try expectMatrix4x4(
        Matrix4x4.init(
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            -3.0,
            -3.0,
            -3.0,
            0.0,
        ),
        a.sub(b),
    );
    try expectMatrix4x4(
        Matrix4x4.translation(5.0, 7.0, 9.0),
        a.mul(b),
    );
    try expectMatrix4x4(
        Matrix4x4.init(
            2.0,
            0.0,
            0.0,
            0.0,
            0.0,
            2.0,
            0.0,
            0.0,
            0.0,
            0.0,
            2.0,
            0.0,
            2.0,
            4.0,
            6.0,
            2.0,
        ),
        a.mulScalar(2.0),
    );
}
