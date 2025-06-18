const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});

const width = 800;
const height = 600;
const FPS = 60;
const DELTA_TIME_SPEC = 1.0 / @as(f32, FPS);
const BALL_SPEED = 500;
const BALL_SIZE = 50;
const BAR_LEN = 100;
const BAR_THICKNESS = 10;
const BAR_Y = height - BAR_THICKNESS - 100;
const TARGET_WIDTH = 100;
const TARGET_HEIGHT = 10;
const TARGETS_CAP = 128;
const TARGET_PADDING = 20;

// Target grid configuration
const TARGETS_PER_ROW = 5;
const TARGET_ROWS = 4;
const TARGETS_START_X = 100;
const TARGETS_START_Y = 100;

const Target = struct{
    x: f32,
    y: f32,
    isdead: bool = false
};

var targets_pool: [TARGETS_CAP]Target = undefined;
var targets_pool_count: usize = 0;

var bar_x: f32 = width/2 - BAR_LEN/2;
var ball_x: f32 = width/2 - BALL_SIZE;
var ball_y: f32 = BAR_Y - BAR_THICKNESS/2 - BALL_SIZE/2;
var ball_dx: f32 = 0;
var ball_dy: f32 = 0;   
var started: bool = false;
var isPaused: bool = false;

fn initTargets() void {
    targets_pool_count = 0;
    
    var row: usize = 0;
    while (row < TARGET_ROWS and targets_pool_count < TARGETS_CAP) : (row += 1) {
        var col: usize = 0;
        while (col < TARGETS_PER_ROW and targets_pool_count < TARGETS_CAP) : (col += 1) {
            targets_pool[targets_pool_count] = Target{
                .x = TARGETS_START_X + @as(f32, @floatFromInt(col)) * (TARGET_WIDTH + TARGET_PADDING),
                .y = TARGETS_START_Y + @as(f32, @floatFromInt(row)) * (TARGET_HEIGHT + TARGET_PADDING),
                .isdead = false
            };
            targets_pool_count += 1;
        }
    }
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
        // Set initial ball velocity
        ball_dx = 0.7; // Move diagonally up-right
        ball_dy = -0.7; // Negative for upward movement
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
    }
    if (next_pos.y < 0) {
        ball_dy *= -1;
        next_pos.y = ball_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC;
    }
    if (next_pos.y + BALL_SIZE > height) {
        ball_dy *= -1;
        next_pos.y = ball_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC;
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
    
    // Determine collision side and respond
    if (ball_center_y < paddle_top) {
        // Hit from above - vertical bounce
        ball_dy *= -1;
        next_pos.y = paddle_top - BALL_SIZE;
    } 
    else if (ball_center_y > paddle_bottom) {
        // Hit from below - vertical bounce
        ball_dy *= -1;
        next_pos.y = paddle_bottom;
    }
    else if (ball_center_x < paddle_left) {
        // Hit from left - horizontal bounce
        ball_dx *= -1;
        next_pos.x = paddle_left - BALL_SIZE;
    }
    else if (ball_center_x > paddle_right) {
        // Hit from right - horizontal bounce
        ball_dx *= -1;
        next_pos.x = paddle_right;
    }
    else {
        // Default to vertical bounce
        ball_dy *= -1;
        next_pos.y = prev_y + ball_dy * BALL_SPEED * DELTA_TIME_SPEC;
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
                
                // Calculate distance from ball center to target center
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
    
    // Mark target as destroyed
    targets_pool[target_index].isdead = true;
    
    // Calculate collision direction based on ball's previous position
    const ball_prev_cx = prev_pos.x + BALL_SIZE / 2;
    const ball_prev_cy = prev_pos.y + BALL_SIZE / 2;
    const target_cx = target.x + TARGET_WIDTH / 2;
    const target_cy = target.y + TARGET_HEIGHT / 2;
    
    const dx = ball_prev_cx - target_cx;
    const dy = ball_prev_cy - target_cy;
    
    // Determine bounce direction based on which side had greater separation
    if (@abs(dx) > @abs(dy)) {
        // Horizontal collision
        ball_dx *= -1;
        if (dx > 0) {
            next_pos.x = target.x + TARGET_WIDTH; // move to right of target
        } else {
            next_pos.x = target.x - BALL_SIZE; // move to left of target
        }
    } else {
        // Vertical collision
        ball_dy *= -1;
        if (dy > 0) {
            next_pos.y = target.y + TARGET_HEIGHT; // below the target
        } else {
            next_pos.y = target.y - BALL_SIZE; // above the target
        }
    }
}

fn updatePaddle() void {
    if (rl.IsKeyDown(rl.KEY_RIGHT)) {
        bar_x += 10;
        if (bar_x + BAR_LEN > width) bar_x = width - BAR_LEN;
    }
    if (rl.IsKeyDown(rl.KEY_LEFT)) {
        bar_x -= 10;
        if (bar_x < 0) bar_x = 0;
    }
}

fn update() void {
    if (isPaused) return;

    // Handle input to start the game
    if (!started and (rl.IsKeyDown(rl.KEY_RIGHT) or rl.IsKeyDown(rl.KEY_LEFT))) {
        startGame();
    }

    // Store previous position
    const prev_pos = BallPosition{ .x = ball_x, .y = ball_y };
    
    // Calculate next position
    var next_pos = updateBallPosition();

    if (started) {
        handleWallCollisions(&next_pos);
        handlePaddleCollision(&next_pos, prev_pos.y);
        
        // Handle target collisions
        if (findClosestTargetCollision(next_pos)) |target_index| {
            handleTargetCollision(&next_pos, prev_pos, target_index);
        }
    }
    
    updatePaddle();
    
    ball_x = next_pos.x;
    ball_y = next_pos.y;
}

fn render() void {
    rl.BeginDrawing();
    rl.ClearBackground(rl.BLACK);
    
    rl.DrawCircle(
        @intFromFloat(ball_x + BALL_SIZE / 2),  // x center
        @intFromFloat(ball_y + BALL_SIZE / 2),  // y center
        BALL_SIZE / 2,                          // radius
        rl.RED
    );
    
    rl.DrawRectangle(@intFromFloat(bar_x), @intFromFloat(BAR_Y - BAR_THICKNESS / 2), BAR_LEN, BAR_THICKNESS, rl.RAYWHITE);
    
    // Render only active targets
    for(targets_pool[0..targets_pool_count]) |target|{
        if(!target.isdead){
            rl.DrawRectangle(@intFromFloat(target.x),@intFromFloat(target.y),TARGET_WIDTH,TARGET_HEIGHT,rl.GREEN);
        }
    }
    
    // Show instructions if game hasn't started
    if (!started) {
        const text = "Press LEFT or RIGHT arrow to start";
        const text_width = rl.MeasureText(text, 20);
        const x = @divTrunc(width - text_width, 2);
        const y = height - 50;
        rl.DrawText(text, x, y, 20, rl.WHITE);
    }
    
    rl.EndDrawing();  
}

fn renderPaused() void {
    rl.BeginDrawing();
    rl.ClearBackground(rl.LIGHTGRAY);

    const text_width = rl.MeasureText("PAUSED", 40);
    const x = 400 - @divTrunc(text_width, 2);
    const y = 300 - 20;
    rl.DrawText("PAUSED", x, y, 40, rl.GRAY);

    rl.EndDrawing();
}

pub fn main() !void {
    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.InitWindow(width, height, "Breakout Game - Zig");
    rl.SetTargetFPS(FPS);
    defer rl.CloseWindow();

    // Initialize targets at startup
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
