package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"
import "core:mem"

import sa "core:container/small_array"

import "../ldtk"

v2 :: dm.v2
iv2 :: dm.iv2

windowSize :: iv2{800, 900}

GameState :: struct {
    gameBoardSprite: dm.Sprite,
    mollySprite: dm.Sprite,
    mollyHandsSprite: dm.Sprite,
    holeSprite: dm.Sprite,
    saltSprite: dm.Sprite,
    btnSprite: dm.Sprite,
    btnPressedSprite: dm.Sprite,

    newActiveTimer: f32,

    holes: [HolesCount]HoleData,
    salts: sa.Small_Array(128, SaltData),

    gameBegun: bool,
    score: int,
    timeLeft: f32,
}
gameState: ^GameState

GameTime :: 80

HoleSize :: v2{1, 1}
HoleColliderOffset :: v2{0, -0.17}
HolesCount :: 3

HoleState :: enum {
    Dormant,
    Showing,
    Active,
    Hit,
    Hiding,
}

HoleData :: struct {
    state: HoleState,
    stateTime: f32,

    targeted: bool,
    targetPos: v2,
}

HolePositions := [HolesCount]v2{
    {0, 0},
    {1, -1},
    {-1, -1},
}


BaseStateTimes := [HoleState]f32 {
    .Dormant = 0,
    .Showing = 1,
    .Active = 300,
    .Hit = 0.2,
    .Hiding = 0.1,
}

SaltData :: struct {
    start, end: v2,
    airTime: f32,

    targetedHole: int,

    position: v2,
    speed: v2,

    rotation: f32,
    rotationSpeed: f32,
}

@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    dm.RegisterAsset("assets.png", dm.TextureAssetDescriptor{})

    dm.platform.SetWindowSize(int(windowSize.x), int(windowSize.y))
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    PixelsPerUnit :: 16

    assetsTex := dm.GetTextureAsset("assets.png")
    gameState.gameBoardSprite = dm.CreateSprite(assetsTex, dm.RectInt{0, 0, 8 * 16, 11 * 16})
    gameState.gameBoardSprite.scale = f32(gameState.gameBoardSprite.textureSize.x) / PixelsPerUnit

    gameState.mollySprite = dm.CreateSprite(assetsTex, dm.RectInt{128, 32, 16, 16})
    gameState.mollySprite.origin = {0.5, 1}

    gameState.mollyHandsSprite = dm.CreateSprite(assetsTex, dm.RectInt{128, 48, 16, 6})
    gameState.holeSprite = dm.CreateSprite(assetsTex, dm.RectInt{127, 16, 18, 16})
    gameState.holeSprite.scale = f32(gameState.holeSprite.textureSize.x) / PixelsPerUnit

    gameState.saltSprite = dm.CreateSprite(assetsTex, dm.RectInt{128, 64, 16, 16})
    gameState.saltSprite.scale = 0.5

    gameState.btnSprite = dm.CreateSprite(assetsTex, dm.RectInt{128, 80, 16, 16})
    gameState.btnPressedSprite = dm.CreateSprite(assetsTex, dm.RectInt{128 + 16, 80, 16, 16})

    platform.renderCtx.camera.orthoSize = 5.5
    platform.renderCtx.camera.aspect = f32(windowSize.x)/f32(windowSize.y)

    StartGame()
}

ResetGame :: proc() {

}

StartGame :: proc() {
    gameState.gameBegun = true
    gameState.timeLeft = GameTime
}

SwitchHoleState :: proc(hole: ^HoleData, state: HoleState) {
    hole.state = state
    hole.stateTime = BaseStateTimes[state]
}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state

    if gameState.gameBegun {
        gameState.timeLeft -= dm.time.deltaTime
    }

    gameState.newActiveTimer += dm.time.deltaTime
    if gameState.newActiveTimer > 1 {
        gameState.newActiveTimer = 0

        randIdx := rand.uint32() % HolesCount
        for i in 0..<HolesCount {
            idx := (int(randIdx) + i) % HolesCount

            if gameState.holes[idx].state == .Dormant {
                SwitchHoleState(&gameState.holes[idx], .Showing)

                break
            }
        }
    }


    for &hole, i in gameState.holes {
        hole.stateTime -= dm.time.deltaTime

        if hole.state == .Showing || hole.state == .Active {
            pos := HolePositions[i] + HoleColliderOffset

            mouse := dm.ToV2(dm.ScreenToWorldSpace(dm.input.mousePos))
            bounds := dm.CreateBounds(pos, HoleSize, anchor = {0.5, 0})
            isInBound := dm.IsInBounds(bounds, mouse.xy)

            color := isInBound ? dm.RED : dm.GREEN
            color.a = 0.2

            dm.DrawBounds2D(dm.renderCtx, bounds, false, color = color)

            if isInBound && dm.GetMouseButton(.Left) == .JustPressed {
                delta := mouse - HolePositions[i]

                cameraBounds := dm.GetCameraBounds(dm.renderCtx.camera)
                ray := dm.CreateRay2D(HolePositions[i], delta)
                ray.direction.y = abs(ray.direction.y)

                _, dist := dm.RaycastAABB2D(ray, cameraBounds)

                salt := SaltData {
                    start = dm.PointAtRay(ray, dist),
                    end = mouse,
                    rotationSpeed = rand.float32() * 10 - 5,
                    targetedHole = i,
                }

                sa.append(&gameState.salts, salt)

                // SwitchHoleState(&hole, .Hit)
                hole.targeted = true
                hole.targetPos = mouse
            }
        }

        if hole.stateTime < 0 {
            if hole.state == .Showing {
                SwitchHoleState(&hole, .Active)
            }
            else if hole.state == .Active && hole.targeted == false {
                SwitchHoleState(&hole, .Hiding)
            }
            else if hole.state == .Hit {
                SwitchHoleState(&hole, .Hiding)
            }
            else if hole.state == .Hiding {
                SwitchHoleState(&hole, .Dormant)
            }
        }
    }

    for i := gameState.salts.len - 1; i >= 0; i -= 1 {
        s := &gameState.salts.data[i]
        s.rotation += s.rotationSpeed * dm.time.deltaTime

        if s.airTime < 1 {
            s.position = math.lerp(s.start, s.end, s.airTime)
            s.airTime += dm.time.deltaTime * 10

            if s.airTime >= 1 {
                // TODO: spawn hit effect
                dir := dm.RandomDirection()
                dir.y = abs(dir.y)

                s.speed = dir * (rand.float32() * 10 + 3)
                s.rotationSpeed = rand.float32() * 20 - 10

                hole := &gameState.holes[s.targetedHole]
                hole.targeted = false
                SwitchHoleState(hole, .Hit)
            }

        }
        else {
            s.speed += v2{0, -20} * dm.time.deltaTime
            s.position += s.speed * dm.time.deltaTime

            if dm.IsInsideCamera(dm.renderCtx.camera, s.position, gameState.saltSprite) == false {
                sa.unordered_remove(&gameState.salts, i)
            }
        }
    }
}


@(export)
GameUpdateDebug : dm.GameUpdateDebug : proc(state: rawptr, debug: bool) {
    gameState = cast(^GameState) state

}

@(export)
GameRender : dm.GameRender : proc(state: rawptr) {
    gameState = cast(^GameState) state
    dm.ClearColor({0.0/255.0, 24.0/255.0, 4.0/255.0, 1})

    dm.DrawSprite(gameState.gameBoardSprite, {0, 0})

    for &hole, i in gameState.holes {
        dm.DrawSprite(gameState.holeSprite, HolePositions[i])

        if hole.state != .Dormant {
            sprite := gameState.mollySprite
            pos := HolePositions[i] + HoleColliderOffset
            color := dm.WHITE

            if hole.state == .Showing {
                p := 1 - hole.stateTime / BaseStateTimes[hole.state]
                sprite.textureSize.y = i32(min(1, p) * f32(sprite.textureSize.y))
            }
            else if hole.state == .Hiding {
                p := hole.stateTime / BaseStateTimes[hole.state]
                sprite.textureSize.y = i32(min(1, p) * f32(sprite.textureSize.y))
            }
            if hole.state == .Hit {
                color = dm.RED
            }

            dm.DrawSprite(sprite, pos, color = color)
            dm.DrawSprite(gameState.mollyHandsSprite, HolePositions[i] - {0, 0.2}, color = color)
        }
    }

    dm.DrawSprite(gameState.btnSprite, {-2, -4.3})
    dm.DrawSprite(gameState.btnSprite, {2, -4.3})

    dm.DrawTextCentered(dm.renderCtx, "999", dm.LoadDefaultFont(dm.renderCtx), {280, 280}, color = {1, 1, 1, 1}, fontSize = 70)
    dm.DrawTextCentered(dm.renderCtx, fmt.tprintf("%.2f",gameState.timeLeft), dm.LoadDefaultFont(dm.renderCtx), {520, 280}, color = {1, 1, 1, 1}, fontSize = 70)

    for i in 0..<gameState.salts.len {
        s := &gameState.salts.data[i]
        dm.DrawSprite(gameState.saltSprite, s.position, rotation = s.rotation)
    }

    dm.DrawGrid()
}
