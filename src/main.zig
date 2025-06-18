const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});

const width = 800;
const height = 600;
const FPS = 60;
const DELTA_TIME_SPEC = 1.0 / @as(f32, FPS);
const BALL_SPEED = 400;
const BALL_SIZE = 20;
const BAR_LEN = 120;
const BAR_THICKNESS = 12;
const BAR_Y = height - BAR_THICKNESS - 80;
const TARGET_WIDTH = 80;
const TARGET_HEIGHT = 25;
const TARGETS_CAP = 128;
const TARGET_PADDING = 8;

// Target grid configuration
const TARGETS_PER_ROW = 8;
const TARGET_ROWS = 6;
const TARGETS_START_X = 80;
const TARGETS_START_Y = 80;

// Particle system
const MAX_PARTICLES = 100;
const PARTICLE_LIFE = 60; // frames

const Target = struct{
    x: f32,
    y: f32,
    isdead: bool = false,
    color: rl.Color,
    scale: f32 = 1.0,
    hit_animation: f32 = 0.0,
};

const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: i32,
    color: rl.Color,
    size: f32,
};

const Trail = struct {
    x: f32,
    y: f32,
    alpha: f32,
};

var targets_pool: [TARGETS_CAP]Target = undefined;
var targets_pool_count: usize = 0;
var particles: [MAX_PARTICLES]Particle = undefined;
var particle_count: usize = 0;
var trail: [20]Trail = undefined;
var trail_index: usize = 0;

var bar_x: f32 = width/2 - BAR_LEN/2;
var ball_x: f32 = width/2 - BALL_SIZE;
var ball_y: f32 = BAR_Y - BAR_THICKNESS/2 - BALL_SIZE/2;
var ball_dx: f32 = 0;
var ball_dy: f32 = 0;   
var started: bool = false;
var isPaused: bool = false;
var game_time: f32 = 0;
var ball_glow: f32 = 0;
var paddle_glow: f32 = 0;

// Color palette
const COLOR_BG_START = rl.Color{.r = 15, .g = 15, .b = 35, .a = 255};
const COLOR_BG_END = rl.Color{.r = 25, .g = 25, .b = 55, .a = 255};
const COLOR_BALL = rl.Color{.r = 255, .g = 100, .b = 150, .a = 255};
const COLOR_BALL_GLOW = rl.Color{.r = 255, .g = 150, .b = 200, .a = 100};
const COLOR_PADDLE = rl.Color{.r = 100, .g = 200, .b = 255, .a = 255};
const COLOR_PADDLE_GLOW = rl.Color{.r = 150, .g = 220, .b = 255, .a = 80};

fn getTargetColor(row: usize) rl.Color {
    const colors = [_]rl.Color{
        rl.Color{.r = 255, .g = 80, .b = 80, .a = 255},   // Red
        rl.Color{.r = 255, .g = 150, .b = 80, .a = 255},  // Orange
        rl.Color{.r = 255, .g = 220, .b = 80, .a = 255},  // Yellow
        rl.Color{.r = 80, .g = 255, .b = 80, .a = 255},   // Green
        rl.Color{.r = 80, .g = 150, .b = 255, .a = 255},  // Blue
        rl.Color{.r = 180, .g = 80, .b = 255, .a = 255},  // Purple
    };
    return colors[row % colors.len];
}

fn initTargets() void {
    targets_pool_count = 0;
    
    var row: usize = 0;
    while (row < TARGET_ROWS and targets_pool_count < TARGETS_CAP) : (row += 1) {
        var col: usize = 0;
        while (col < TARGETS_PER_ROW and targets_pool_count < TARGETS_CAP) : (col += 1) {
            targets_pool[targets_pool_count] = Target{
                .x = TARGETS_START_X + @as(f32, @floatFromInt(col)) * (TARGET_WIDTH + TARGET_PADDING),
                .y = TARGETS_START_Y + @as(f32, @floatFromInt(row)) * (TARGET_HEIGHT + TARGET_PADDING),
                .isdead = false,
                .color = getTargetColor(row),
                .scale = 1.0,
            };
            targets_pool_count += 1;
        }
    }
}

fn addParticle(x: f32, y: f32, color: rl.Color) void {
    if (particle_count >= MAX_PARTICLES) return;
    
    const angle = @as(f32, @floatFromInt(std.crypto.random.int(u32))) / @as(f32, @floatFromInt(std.math.maxInt(u32))) * 2.0 * std.math.pi;
    const speed = 2.0 + @as(f32, @floatFromInt(std.crypto.random.int(u32) % 100)) / 50.0;
    
    particles[particle_count] = Particle{
        .x = x,
        .y = y,
        .vx = @cos(angle) * speed,
        .vy = @sin(angle) * speed,
        .life = PARTICLE_LIFE,
        .color = color,
        .size = 2.0 + @as(f32, @floatFromInt(std.crypto.random.int(u32) % 30)) / 10.0,
    };
    particle_count += 1;
}

fn updateParticles() void {
    var i: usize = 0;
    while (i < particle_count) {
        particles[i].x += particles[i].vx;
        particles[i].y += particles[i].vy;
        particles[i].vy += 0.1; // gravity
        particles[i].life -= 1;
        
        if (particles[i].life <= 0) {
            particles[i] = particles[particle_count - 1];
            particle_count -= 1;
        } else {
            i += 1;
        }
    }
}

fn updateTrail() void {
    trail[trail_index] = Trail{
        .x = ball_x + BALL_SIZE / 2,
        .y = ball_y + BALL_SIZE / 2,
        .alpha = 1.0,
    };
    trail_index = (trail_index + 1) % trail.len;
    
    // Fade existing trail
    for (&trail) |*t| {
        t.alpha *= 0.9;
    }
}

fn drawGradientBackground() void {
    const steps = 20;
    const step_height = @as(f32, height) / @as(f32, steps);
    
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, steps);
        const color = rl.Color{
            .r = @as(u8, @intFromFloat(@as(f32, COLOR_BG_START.r) * (1.0 - t) + @as(f32, COLOR_BG_END.r) * t)),
            .g = @as(u8, @intFromFloat(@as(f32, COLOR_BG_START.g) * (1.0 - t) + @as(f32, COLOR_BG_END.g) * t)),
            .b = @as(u8, @intFromFloat(@as(f32, COLOR_BG_START.b) * (1.0 - t) + @as(f32, COLOR_BG_END.b) * t)),
            .a = 255,
        };
        
        rl.DrawRectangle(0, @intFromFloat(@as(f32, @floatFromInt(i)) * step_height), width, @intFromFloat(step_height + 1), color);
    }
}

fn drawGlowCircle(x: i32, y: i32, radius: f32, color: rl.Color, glow_color: rl.Color) void {
    // Draw glow layers
    var glow_radius = radius * 3;
    while (glow_radius > radius) {
        const alpha = @as(u8, @intFromFloat(20.0 * (radius / glow_radius)));
        const glow = rl.Color{.r = glow_color.r, .g = glow_color.g, .b = glow_color.b, .a = alpha};
        rl.DrawCircle(x, y, glow_radius, glow);
        glow_radius -= 2;
    }
    
    // Draw main circle
    rl.DrawCircle(x, y, radius, color);
}

fn drawGlowRect(x: i32, y: i32, w: i32, h: i32, color: rl.Color, glow_color: rl.Color) void {
    // Draw glow
    var glow_offset: i32 = 5;
    while (glow_offset > 0) {
        const alpha = @as(u8, @intFromFloat(30.0 / @as(f32, @floatFromInt(glow_offset))));
        const glow = rl.Color{.r = glow_color.r, .g = glow_color.g, .b = glow_color.b, .a = alpha};
        rl.DrawRectangle(x - glow_offset, y - glow_offset, w + glow_offset * 2, h + glow_offset * 2, glow);
        glow_offset -= 1;
    }
    
    // Draw main rectangle
    rl.DrawRectangle(x, y, w, h, color);
}

fn rectsIntersect(x1: f32, y1: f32, w1: f32, h1: f32,
                  x2: f32, y2: f32, w2: f32, h2: f32) bool {
     return x1 < x2 + w2 and
           x1 + w1 > x2 and
           y1 < y2 + h2 and
           y1 + h1 > y2;   
}

const BallPosition = struct {
    x: f32,
    y: f32,
};

fn startGame() void {
    if (!started) {
        started = true;
        ball_dx = 0.7;
        ball_dy = -0.7;
    }
}

fn updateBallPosition() BallPosition {
    if (!started) {
        return BallPosition{
            .x = bar_x + BAR_LEN/2 - BALL_SIZE/2,
            .y = BAR_Y - BAR_THICKNESS/2 - BALL_SIZE,
        };
    }
    return BallPosition{
        .x = ball_x + ball_dx * BALL_SPEED * DELTA_TIME_SPEC,
        .y = ball_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC,
    };
}

fn handleWallCollisions(next_pos: *BallPosition) void {
    if (next_pos.x < 0 or next_pos.x + BALL_SIZE > width) {
        ball_dx *= -1;
        next_pos.x = ball_x + ball_dx * BALL_SPEED * DELTA_TIME_SPEC;
        ball_glow = 30;
    }
    if (next_pos.y < 0) {
        ball_dy *= -1;
        next_pos.y = ball_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC;
        ball_glow = 30;
    }
    if (next_pos.y + BALL_SIZE > height) {
        ball_dy *= -1;
        next_pos.y = ball_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC;
        ball_glow = 30;
    }
}

fn handlePaddleCollision(next_pos: *BallPosition, prev_y: f32) void {
    const bar_rect_y = BAR_Y - BAR_THICKNESS / 2;
    
    if (!rectsIntersect(next_pos.x, next_pos.y, BALL_SIZE, BALL_SIZE,
                       bar_x, bar_rect_y, BAR_LEN, BAR_THICKNESS)) {
        return;
    }
    
    const ball_center_x = ball_x + BALL_SIZE / 2;
    const ball_center_y = ball_y + BALL_SIZE / 2;
    
    const paddle_left = bar_x;
    const paddle_right = bar_x + BAR_LEN;
    const paddle_top = bar_rect_y;
    const paddle_bottom = bar_rect_y + BAR_THICKNESS;
    
    if (ball_center_y < paddle_top) {
        ball_dy *= -1;
        next_pos.y = paddle_top - BALL_SIZE;
        paddle_glow = 30;
        ball_glow = 30;
    } 
    else if (ball_center_y > paddle_bottom) {
        ball_dy *= -1;
        next_pos.y = paddle_bottom;
        paddle_glow = 30;
        ball_glow = 30;
    }
    else if (ball_center_x < paddle_left) {
        ball_dx *= -1;
        next_pos.x = paddle_left - BALL_SIZE;
        paddle_glow = 30;
        ball_glow = 30;
    }
    else if (ball_center_x > paddle_right) {
        ball_dx *= -1;
        next_pos.x = paddle_right;
        paddle_glow = 30;
        ball_glow = 30;
    }
    else {
        ball_dy *= -1;
        next_pos.y = prev_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC;
        paddle_glow = 30;
        ball_glow = 30;
    }
}

fn findClosestTargetCollision(next_pos: BallPosition) ?usize {
    var closest_target_index: usize = 0;
    var closest_distance: f32 = std.math.inf(f32);
    var hit_target = false;
    
    for (targets_pool[0..targets_pool_count], 0..) |target, i| {
        if (!target.isdead) {
            if (rectsIntersect(next_pos.x, next_pos.y, BALL_SIZE, BALL_SIZE,
                              target.x, target.y, TARGET_WIDTH, TARGET_HEIGHT)) {
                
                const ball_center_x = ball_x + BALL_SIZE / 2;
                const ball_center_y = ball_y + BALL_SIZE / 2;
                const target_center_x = target.x + TARGET_WIDTH / 2;
                const target_center_y = target.y + TARGET_HEIGHT / 2;
                
                const dx = ball_center_x - target_center_x;
                const dy = ball_center_y - target_center_y;
                const distance = dx * dx + dy * dy;
                
                if (distance < closest_distance) {
                    closest_distance = distance;
                    closest_target_index = i;
                    hit_target = true;
                }
            }
        }
    }
    
    return if (hit_target) closest_target_index else null;
}

fn handleTargetCollision(next_pos: *BallPosition, prev_pos: BallPosition, target_index: usize) void {
    const target = targets_pool[target_index];
    
    // Add particles at impact
    const impact_x = target.x + TARGET_WIDTH / 2;
    const impact_y = target.y + TARGET_HEIGHT / 2;
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        addParticle(impact_x, impact_y, target.color);
    }
    
    targets_pool[target_index].isdead = true;
    ball_glow = 30;
    
    const ball_prev_cx = prev_pos.x + BALL_SIZE / 2;
    const ball_prev_cy = prev_pos.y + BALL_SIZE / 2;
    const target_cx = target.x + TARGET_WIDTH / 2;
    const target_cy = target.y + TARGET_HEIGHT / 2;
    
    const dx = ball_prev_cx - target_cx;
    const dy = ball_prev_cy - target_cy;
    
    if (@abs(dx) > @abs(dy)) {
        ball_dx *= -1;
        if (dx > 0) {
            next_pos.x = target.x + TARGET_WIDTH;
        } else {
            next_pos.x = target.x - BALL_SIZE;
        }
    } else {
        ball_dy *= -1;
        if (dy > 0) {
            next_pos.y = target.y + TARGET_HEIGHT;
        } else {
            next_pos.y = target.y - BALL_SIZE;
        }
    }
}

fn updatePaddle() void {
    if (rl.IsKeyDown(rl.KEY_RIGHT)) {
        bar_x += 8;
        if (bar_x + BAR_LEN > width) bar_x = width - BAR_LEN;
    }
    if (rl.IsKeyDown(rl.KEY_LEFT)) {
        bar_x -= 8;
        if (bar_x < 0) bar_x = 0;
    }
}

fn update() void {
    if (isPaused) return;

    game_time += DELTA_TIME_SPEC;
    
    // Decay glow effects
    if (ball_glow > 0) ball_glow -= 1;
    if (paddle_glow > 0) paddle_glow -= 1;

    if (!started and (rl.IsKeyDown(rl.KEY_RIGHT) or rl.IsKeyDown(rl.KEY_LEFT))) {
        startGame();
    }

    const prev_pos = BallPosition{ .x = ball_x, .y = ball_y };
    var next_pos = updateBallPosition();

    if (started) {
        updateTrail();
        handleWallCollisions(&next_pos);
        handlePaddleCollision(&next_pos, prev_pos.y);
        
        if (findClosestTargetCollision(next_pos)) |target_index| {
            handleTargetCollision(&next_pos, prev_pos, target_index);
        }
    }
    
    updatePaddle();
    updateParticles();
    
    ball_x = next_pos.x;
    ball_y = next_pos.y;
}

fn render() void {
    rl.BeginDrawing();
    
    // Draw gradient background
    drawGradientBackground();
    
    // Draw trail
    for (trail) |t| {
        if (t.alpha > 0.1) {
            const alpha = @as(u8, @intFromFloat(t.alpha * 100));
            const trail_color = rl.Color{.r = COLOR_BALL.r, .g = COLOR_BALL.g, .b = COLOR_BALL.b, .a = alpha};
            const size = 3.0 * t.alpha;
            rl.DrawCircle(@intFromFloat(t.x), @intFromFloat(t.y), size, trail_color);
        }
    }
    
    // Draw ball with glow
    const ball_glow_intensity = if (ball_glow > 0) 1.0 + ball_glow / 30.0 else 1.0;
    drawGlowCircle(
        @intFromFloat(ball_x + BALL_SIZE / 2),
        @intFromFloat(ball_y + BALL_SIZE / 2),
        BALL_SIZE / 2 * ball_glow_intensity,
        COLOR_BALL,
        COLOR_BALL_GLOW
    );
    
    // Draw paddle with glow
    const paddle_glow_intensity = if (paddle_glow > 0) COLOR_PADDLE_GLOW else rl.Color{.r = 0, .g = 0, .b = 0, .a = 0};
    drawGlowRect(
        @intFromFloat(bar_x),
        @intFromFloat(BAR_Y - BAR_THICKNESS / 2),
        BAR_LEN,
        BAR_THICKNESS,
        COLOR_PADDLE,
        paddle_glow_intensity
    );
    
    // Draw targets with subtle animations
    for(targets_pool[0..targets_pool_count]) |target|{
        if(!target.isdead){
            const shimmer = @sin(game_time * 2.0 + target.x * 0.01) * 0.1 + 1.0;
            const tcr:f32 = @floatFromInt(target.color.r);
            const tcg:f32 = @floatFromInt(target.color.g);
            const tcb:f32 = @floatFromInt(target.color.b);
            
            const shimmer_color = rl.Color{
                .r = @intFromFloat( @min(255, @as(f32,(@as(f32, tcr) * shimmer)))),
                .g = @intFromFloat(@min(255, @as(f32,(@as(f32, tcg) * shimmer)))),
                .b = @intFromFloat(@min(255, @as(f32,(@as(f32, tcb) * shimmer)))),
                .a = target.color.a,
            };
            
            // Draw slight glow
            const glow_color = rl.Color{.r = target.color.r, .g = target.color.g, .b = target.color.b, .a = 30};
            rl.DrawRectangle(
                @intFromFloat(target.x - 2),
                @intFromFloat(target.y - 2),
                TARGET_WIDTH + 4,
                TARGET_HEIGHT + 4,
                glow_color
            );
            
            // Draw main target
            rl.DrawRectangle(
                @intFromFloat(target.x),
                @intFromFloat(target.y),
                TARGET_WIDTH,
                TARGET_HEIGHT,
                shimmer_color
            );
        }
    }
    
    // Draw particles
    for (particles[0..particle_count]) |particle| {
        const life_ratio = @as(f32, @floatFromInt(particle.life)) / @as(f32, PARTICLE_LIFE);
        const alpha = @as(u8, @intFromFloat(life_ratio * 255));
        const particle_color = rl.Color{
            .r = particle.color.r,
            .g = particle.color.g,
            .b = particle.color.b,
            .a = alpha,
        };
        rl.DrawCircle(
            @intFromFloat(particle.x),
            @intFromFloat(particle.y),
            particle.size * life_ratio,
            particle_color
        );
    }
    
    // Show instructions with glow effect
    if (!started) {
        const text = "Press LEFT or RIGHT arrow to start";
        const text_width = rl.MeasureText(text, 24);
        const x = @divTrunc(width - text_width, 2);
        const y = height - 60;
        
        // Draw text glow
        const glow_color = rl.Color{.r = 255, .g = 255, .b = 255, .a = 100};
        rl.DrawText(text, x - 1, y - 1, 24, glow_color);
        rl.DrawText(text, x + 1, y - 1, 24, glow_color);
        rl.DrawText(text, x - 1, y + 1, 24, glow_color);
        rl.DrawText(text, x + 1, y + 1, 24, glow_color);
        
        // Draw main text
        rl.DrawText(text, x, y, 24, rl.WHITE);
    }
    
    rl.EndDrawing();  
}

fn renderPaused() void {
    rl.BeginDrawing();
    drawGradientBackground();

    const text_width = rl.MeasureText("PAUSED", 60);
    const x = 400 - @divTrunc(text_width, 2);
    const y = 300 - 30;
    
    // Draw glow effect
    const glow_color = rl.Color{.r = 100, .g = 200, .b = 255, .a = 150};
    rl.DrawText("PAUSED", x - 2, y - 2, 60, glow_color);
    rl.DrawText("PAUSED", x + 2, y - 2, 60, glow_color);
    rl.DrawText("PAUSED", x - 2, y + 2, 60, glow_color);
    rl.DrawText("PAUSED", x + 2, y + 2, 60, glow_color);
    
    rl.DrawText("PAUSED", x, y, 60, rl.WHITE);

    rl.EndDrawing();
}

pub fn main() !void {
    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(width, height, "Aesthetic Breakout - Zig");
    rl.SetTargetFPS(FPS);
    defer rl.CloseWindow();

    initTargets();

    while (!rl.WindowShouldClose()) {
        if (rl.IsKeyPressed(rl.KEY_SPACE)) {
            isPaused = !isPaused;
        }

        if (!isPaused) {
            update();
            render();
        } else {
            renderPaused();
        }
    }
}
