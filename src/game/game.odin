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
    bgSprite: dm.Sprite,
    mollySprite: dm.Sprite,
    mollyHitSprite: dm.Sprite,
    mollyHandsSprite: dm.Sprite,
    holeSprite: dm.Sprite,
    saltSprite: dm.Sprite,
    btnSprite: dm.Sprite,
    btnPressedSprite: dm.Sprite,

    font: dm.FontHandle,

    newActiveTimer: f32,

    holes: [HolesCount]HoleData,
    salts: sa.Small_Array(128, SaltData),

    saltParticles: dm.ParticleSystem,

    startBtnPressed: bool,
    flipBtnPressed: bool,

    flipAvailble: bool,
    flipActive: bool,
    flipTimer: f32,

    gameBegun: bool,
    score: int,
    timeLeft: f32,

    pp1: dm.PPHandle,
    ppData: PPData,

    blurPP: dm.PPHandle,
}
gameState: ^GameState

GameTime :: 60

HoleSize :: v2{1, 1}
HoleColliderOffset :: v2{0, -0.27}
HolesCount :: 7

BaseSpawnTime :: 1

FlipInterval :: 10
FlipDuration :: 7

FlipButtonPos :: v2{-2, -4.3}
StartButtonPos :: v2{2, -4.3}

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
    { 1.5, -0.2},
    {-1.5, -0.2},

    {0, -1.2},
    { 2.2, -2.3},
    {-2.2, -2.3},

    {0, -2.8},
}


BaseStateTimes := [HoleState]f32 {
    .Dormant = 0,
    .Showing = .7,
    .Active = 2.5,
    .Hit = 0.4,
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

PPData :: struct #align(16) {
    brightness: f32,
}


@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    dm.RegisterAsset("background.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("assets.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("test.hlsl", dm.ShaderAssetDescriptor{})
    dm.RegisterAsset("Kenney Pixel.ttf", dm.FontAssetDescriptor{.SDF, 50})

    // dm.RegisterAsset("PPEffect.hlsl", dm.ShaderAssetDescriptor{})
    // dm.RegisterAsset("Blur.hlsl", dm.ShaderAssetDescriptor{})
    // dm.RegisterAsset("Vignette.hlsl", dm.ShaderAssetDescriptor{})
    // dm.RegisterAsset("orange hit hard 12.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("orange hit hard 1.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("orange hit hard 5.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 5.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 1.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 3.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 6.wav", dm.SoundAssetDescriptor{})

    // dm.RegisterAsset("Kenney Pixel.ttf", dm.FontAssetDescriptor{
    //     fontType = .SDF,
    //     fontSize = 20,
    // })

    dm.platform.SetWindowSize(int(windowSize.x), int(windowSize.y))
}

@(export)
GameLoad : dm.GameLoad : proc(platform: ^dm.Platform) {
    gameState = dm.AllocateGameData(platform, GameState)

    PixelsPerUnit :: 16

    bgTex := dm.GetTextureAsset("background.png")
    gameState.bgSprite = dm.CreateSprite(bgTex)
    gameState.bgSprite.scale = f32(gameState.bgSprite.textureSize.x) / PixelsPerUnit

    assetsTex := dm.GetTextureAsset("assets.png")

    gameState.mollySprite = dm.CreateSprite(assetsTex, dm.RectInt{0, 0, 20, 20})
    gameState.mollySprite.origin = {0.5, 0}
    gameState.mollySprite.scale = f32(gameState.mollySprite.textureSize.x) / PixelsPerUnit 

    gameState.mollyHitSprite = gameState.mollySprite
    gameState.mollyHitSprite.texturePos.x = 20
    gameState.mollyHitSprite.origin = {0.5, 0.05}

    gameState.mollyHandsSprite = dm.CreateSprite(assetsTex, dm.RectInt{40, 0, 20, 20})
    gameState.mollyHandsSprite.scale = f32(gameState.mollyHandsSprite.textureSize.x) / PixelsPerUnit 
    gameState.holeSprite = dm.CreateSprite(assetsTex, dm.RectInt{0, 20, 20, 20})
    gameState.holeSprite.scale = f32(gameState.holeSprite.textureSize.x) / PixelsPerUnit

    gameState.saltSprite = dm.CreateSprite(assetsTex, dm.RectInt{60, 0, 20, 20})
    gameState.saltSprite.scale = 0.7

    gameState.btnSprite = dm.CreateSprite(assetsTex, dm.RectInt{20, 20, 20, 20})
    gameState.btnSprite.scale = f32(gameState.btnSprite.textureSize.x) / PixelsPerUnit
    gameState.btnPressedSprite = dm.CreateSprite(assetsTex, dm.RectInt{40, 20, 20, 20})
    gameState.btnPressedSprite.scale = f32(gameState.btnPressedSprite.textureSize.x) / PixelsPerUnit

    platform.renderCtx.camera.orthoSize = 5.5
    platform.renderCtx.camera.aspect = f32(windowSize.x)/f32(windowSize.y)

    // gameState.font = dm.LoadFontSDF(platform.renderCtx, "../Assets/Kenney Pixel.ttf", 50)
    gameState.font = cast(dm.FontHandle) dm.GetAsset("Kenney Pixel.ttf")

    // gameState.ppData.brightness = 1.36
    // gameState.blurPP = dm.CreatePostProcess(cast(dm.ShaderHandle) dm.GetAsset("Blur.hlsl"))
    // gameState.pp1 = dm.CreatePostProcess(cast(dm.ShaderHandle) dm.GetAsset("PPEffect.hlsl"), gameState.ppData)
    // dm.CreatePostProcess(cast(dm.ShaderHandle) dm.GetAsset("Vignette.hlsl"))

    // 

    gameState.saltParticles = dm.DefaultParticleSystem
    ps := &gameState.saltParticles
    
    ps.emitRate = 0
    ps.lifetime = 2
    ps.color = dm.color{1, 1, 1, 0.7}
    ps.startRotation = dm.RandomFloat{0, 360}
    ps.startRotationSpeed = dm.RandomFloat{1, 20}
    ps.startSize = dm.RandomFloat{0.05, 0.1}
    ps.texture = dm.renderCtx.whiteTexture
    ps.startSpeed = dm.RandomFloat{1, 4}
    ps.gravity = {0, -20}

    dm.InitParticleSystem(&gameState.saltParticles)
}

ResetGame :: proc() {
    gameState.gameBegun = false

    for &hole, i in gameState.holes {
        hole.state = .Dormant
    }

    gameState.flipAvailble = false
    gameState.flipActive = false

    sa.clear(&gameState.salts)
}

StartGame :: proc() {
    gameState.gameBegun = true
    gameState.timeLeft = GameTime
    gameState.score = 0

    gameState.flipTimer = FlipInterval
}

DifficultyCurve :: proc() -> f32{
    maxPoint :: 0.9
    maxValue :: 0.15
    curv :: 1.5

    t := 1 - (gameState.timeLeft / GameTime)

    if t > maxPoint {
        return maxValue
    }

    curvature: f32 = -(maxValue - 1) / math.pow(f32(maxPoint), curv)
    return -curvature * math.pow(t, curv) + 1
}

SwitchHoleState :: proc(hole: ^HoleData, state: HoleState) {
    hole.state = state
    hole.stateTime = BaseStateTimes[state]

    if state == .Showing || state == .Active {
        hole.stateTime *= DifficultyCurve()
    }
}

HandleButton :: proc(pressed: ^bool, buttonPos: v2, mousePos: v2) -> bool {
    bounds := dm.SpriteBounds(gameState.btnSprite, buttonPos)
    inBounds := dm.IsInBounds(bounds, mousePos)

    mouseBtn := dm.GetMouseButton(.Left)

    if mouseBtn == .JustReleased {
        if pressed^ {
            pressed^ = false
            return inBounds
        }
    }

    if mouseBtn == .JustPressed {
        if inBounds {
            pressed^ = true
        }
    }

    return false
}

@(export)
GameUpdate : dm.GameUpdate : proc(state: rawptr) {
    gameState = cast(^GameState) state

    // dm.renderCtx.camera.rotation += dm.time.deltaTime * 0.1

    mouse := dm.ToV2(dm.ScreenToWorldSpace(dm.input.mousePos))

    // if dm.muiBeginWindow(dm.mui, "PP", {10, 10, 110, 90}) {
    //     dm.muiLabel(dm.mui, fmt.tprint("FlipTimer", gameState.flipTimer))
    //     dm.muiLabel(dm.mui, fmt.tprint("Flip Availble", gameState.flipAvailble))
    //     dm.muiLabel(dm.mui, fmt.tprint("Flip Active", gameState.flipActive))

    //     dm.muiEndWindow(dm.mui);
    // }

    startButtonPressed := HandleButton(&gameState.startBtnPressed, StartButtonPos, mouse)

    if gameState.gameBegun == false {
        if startButtonPressed {
            StartGame()
        }

        return
    }

    if startButtonPressed {
        ResetGame()
    }

    gameState.timeLeft -= dm.time.deltaTime

    gameState.newActiveTimer += dm.time.deltaTime
    if gameState.newActiveTimer > BaseSpawnTime * DifficultyCurve() {
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

            boundsExtend :: 0.2

            bounds := dm.CreateBounds(pos - {0, boundsExtend - 0.05}, HoleSize + boundsExtend, anchor = {0.5, 0})
            isInBound := dm.IsInBounds(bounds, mouse.xy)

            color := isInBound ? dm.RED : dm.GREEN
            color.a = 0.2

            // dm.DrawBounds2D(dm.renderCtx, bounds, false, color = color)

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
                dir := dm.RandomDirection()
                dir.y = abs(dir.y)

                s.speed = dir * (rand.float32() * 10 + 3)
                s.rotationSpeed = rand.float32() * 20 - 10

                hole := &gameState.holes[s.targetedHole]
                hole.targeted = false

                gameState.score += 10

                dm.SpawnParticles(&gameState.saltParticles, 20, 
                    atPosition = hole.targetPos + {0, 0.3},
                    additionalSpeed = cast(v2) glsl.normalize(s.end - s.start) * 5
                )

                sound := cast(dm.SoundHandle) dm.GetAsset("punch 6.wav")
                dm.SetVolume(sound, 0.5)
                dm.PlaySound(sound)

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

    if gameState.flipAvailble {
        if HandleButton(&gameState.flipBtnPressed, FlipButtonPos, mouse) {
            gameState.flipActive = true
            gameState.flipAvailble = false
            gameState.flipTimer = FlipDuration
        }
    }
    else {
        gameState.flipTimer -= dm.time.deltaTime
        if gameState.flipTimer < 0 {
            if gameState.flipActive {
                gameState.flipActive = false
                gameState.flipTimer = FlipInterval
            }
            else {
                gameState.flipAvailble = true
            }
        }
    }

    if gameState.timeLeft < 0 {
        gameState.timeLeft = 0
        ResetGame()
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

    dm.DrawSprite(gameState.bgSprite, {0, 0})

    for &hole, i in gameState.holes {
        dm.DrawSprite(gameState.holeSprite, HolePositions[i])

        if hole.state != .Dormant {
            sprite := gameState.mollySprite
            pos := HolePositions[i] + HoleColliderOffset
            color := dm.WHITE

            if hole.state == .Showing {
                p := 1 - hole.stateTime / (BaseStateTimes[hole.state] * DifficultyCurve())
                sprite.textureSize.y = i32(min(1, p) * f32(sprite.textureSize.y))
            }
            else if hole.state == .Hiding {
                p := hole.stateTime / (BaseStateTimes[hole.state] * DifficultyCurve())
                sprite.textureSize.y = i32(min(1, p) * f32(sprite.textureSize.y))
            }
            if hole.state == .Hit {
                // color = {0.8, 0.8, 0.8, 1}
                sprite = gameState.mollyHitSprite
            }

            dm.DrawSprite(sprite, pos, color = color)
            dm.DrawSprite(gameState.mollyHandsSprite, HolePositions[i] + {0, 0.2}, color = color)
        }
    }

    dm.DrawSprite(
        (gameState.startBtnPressed ? 
            gameState.btnPressedSprite : 
            gameState.btnSprite),
        StartButtonPos
    )

    dm.DrawSprite(
        (gameState.flipBtnPressed || gameState.flipAvailble == false ? 
            gameState.btnPressedSprite : 
            gameState.btnSprite),
        FlipButtonPos
    )


    text := "1.abCDjgeF\n2.LOrem\n3.ipsuM"
    dm.DrawText(
        text,
        {0, 0},
        gameState.font,
        color = {1, 1, 1, 1},
        fontSize = 1
    )

    dm.BeginScreenSpace()
    p := dm.WorldToScreenPoint({-3, 0})
    dm.DrawText(
        text,
        dm.ToV2(p),
        gameState.font,
        color = {1, 1, 1, 1},
        fontSize = 30
    )

    spr := gameState.mollyHitSprite
    spr.scale = 100
    dm.DrawSprite(spr, {100, 100})

    dm.EndScreenSpace()

    // dm.DrawTextCentered(
    //     dm.renderCtx,
    //     "FLIP\nN",
    //     gameState.font,
    //     // dm.ToV2(p) + (flipPressed ? pressedOffset : nonPressedOffset),
    //     FlipButtonPos,
    //     color = {1, 1, 1, 1},
    //     fontSize = 1
    // )

    // dm.BeginScreenSpace()
    //     dm.DrawTextCentered(dm.renderCtx, fmt.tprintf("%5v", gameState.score), gameState.font, {280, 280}, color = {1, 1, 1, 1}, fontSize = 70)
    //     dm.DrawTextCentered(dm.renderCtx, fmt.tprintf("%5.2f",gameState.timeLeft), gameState.font, {525, 280}, color = {1, 1, 1, 1}, fontSize = 70)
    // dm.EndScreenSpace()


    // nonPressedOffset :: v2{3, 10}
    // pressedOffset:: v2{3, 3}

    // p := dm.WorldToScreenPoint(StartButtonPos)
    // dm.DrawTextCentered(
    //     dm.renderCtx, 
    //     "START", 
    //     gameState.font, 
    //     dm.ToV2(p) + (gameState.startBtnPressed ? pressedOffset : nonPressedOffset),
    //     color = {1, 1, 1, 1}, 
    //     fontSize = 20
    // )

    // flipPressed := gameState.flipBtnPressed || gameState.flipAvailble == false
    // p = dm.WorldToScreenPoint(FlipButtonPos)
    // dm.DrawTextCentered(
    //     dm.renderCtx,
    //     "FLIP\nN",
    //     gameState.font,
    //     dm.ToV2(p) + (flipPressed ? pressedOffset : nonPressedOffset),
    //     color = {1, 1, 1, 1},
    //     fontSize = 50
    // )

    for i in 0..<gameState.salts.len {
        s := &gameState.salts.data[i]
        dm.DrawSprite(gameState.saltSprite, s.position, rotation = s.rotation)
    }


    dm.UpdateAndDrawParticleSystem(&gameState.saltParticles)

    dm.PushShader(cast(dm.ShaderHandle) dm.GetAsset("test.hlsl"))

    // // World Space
    {
        cmd: dm.DrawRectCommand

        size := v2{1, 1}

        // texture := dm.renderCtx.whiteTexture
        // texSize := dm.GetTextureSize(texture)
        sp := gameState.mollyHitSprite
        // sp := gameState.mollySprite

        texture := sp.texture


        cmd.position = {2, 2}
        cmd.size = size
        cmd.texSource = {sp.texturePos.x, sp.texturePos.y, sp.textureSize.x, sp.textureSize.y}
        cmd.tint = {1, 1, 1, 1}
        cmd.pivot = sp.origin
        cmd.rotation = f32(dm.time.gameTime)

        cmd.texture = texture
        // cmd.shader = dm.renderCtx.defaultShaders[.Sprite]

        append(&dm.renderCtx.commandBuffer.commands, cmd)
    }

    dm.PopShader()

    // Screen Space
    // dm.BeginScreenSpace()
    // {
    //     cmd: dm.DrawRectCommand

    //     size := v2{100, 100}

    //     // texture := dm.renderCtx.whiteTexture
    //     // texSize := dm.GetTextureSize(texture)
    //     sp := gameState.mollyHitSprite
    //     // sp := gameState.mollySprite

    //     texture := sp.texture


    //     cmd.position = {300, 300}
    //     cmd.size = size
    //     cmd.texSource = {sp.texturePos.x, sp.texturePos.y, sp.textureSize.x, sp.textureSize.y}
    //     cmd.tint = {1, 1, 1, 1}
    //     cmd.pivot = sp.origin
    //     cmd.rotation = f32(dm.time.gameTime)

    //     cmd.texture = texture
    //     // cmd.shader =  shader

    //     append(&dm.renderCtx.commandBuffer.commands, cmd)
    // }
    // dm.EndScreenSpace()

    // dm.PopShader()

    dm.DrawGrid()
}