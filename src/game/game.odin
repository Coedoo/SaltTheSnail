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

    flipAnimActive: bool,
    flipAnimDir: int,
    flipAnimTimer: f32,

    gameBegun: bool,
    score: int,
    timeLeft: f32,

    pp1: dm.PPHandle,
    ppData: PPData,

    blurPP: dm.PPHandle,

    music: dm.SoundHandle,
    hitSounds: sa.Small_Array(16, dm.SoundHandle),
}
gameState: ^GameState

GameTime :: 76

HoleSize :: v2{1, 1}
HoleColliderOffset :: v2{0, -0.27}
HolesCount :: 7

BaseSpawnTime :: 1

FlipInterval :: 10
FlipDuration :: 7

FlipAnimTime :: 0.3

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

HitSoundsNames := [?]string{
    "orange hit hard 1.wav",
    "orange hit hard 5.wav",
    "punch 5.wav",
    "punch 6.wav",
}

@export
PreGameLoad : dm.PreGameLoad : proc(assets: ^dm.Assets) {
    dm.RegisterAsset("background.png", dm.TextureAssetDescriptor{})
    dm.RegisterAsset("assets.png", dm.TextureAssetDescriptor{})
    // dm.RegisterAsset("test.hlsl", dm.ShaderAssetDescriptor{})
    // dm.RegisterAsset("textTest.hlsl", dm.ShaderAssetDescriptor{})
    dm.RegisterAsset("Kenney Pixel.ttf", dm.FontAssetDescriptor{.SDF, 50})

    dm.RegisterAsset("PPEffect.hlsl", dm.ShaderAssetDescriptor{})
    dm.RegisterAsset("Blur.hlsl", dm.ShaderAssetDescriptor{})
    dm.RegisterAsset("Vignette.hlsl", dm.ShaderAssetDescriptor{})



    for name, i in HitSoundsNames {
        dm.RegisterAsset(name, dm.SoundAssetDescriptor{}, key = fmt.tprintf("hit %v", i))
    }

    // dm.RegisterAsset("orange hit hard 12.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("orange hit hard 1.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("orange hit hard 5.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 5.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 1.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 3.wav", dm.SoundAssetDescriptor{})
    // dm.RegisterAsset("punch 6.wav", dm.SoundAssetDescriptor{})
    dm.RegisterAsset("8-bit snel.flac", dm.SoundAssetDescriptor{})
    dm.RegisterAsset("click.wav", dm.SoundAssetDescriptor{})
    dm.RegisterAsset("unclick.wav", dm.SoundAssetDescriptor{})

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

    gameState.ppData.brightness = 1.36
    gameState.blurPP = dm.CreatePostProcess(cast(dm.ShaderHandle) dm.GetAsset("Blur.hlsl"))
    gameState.pp1 = dm.CreatePostProcess(cast(dm.ShaderHandle) dm.GetAsset("PPEffect.hlsl"), gameState.ppData)
    dm.CreatePostProcess(cast(dm.ShaderHandle) dm.GetAsset("Vignette.hlsl"))

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

    ///

    gameState.music = cast(dm.SoundHandle) dm.GetAsset("8-bit snel.flac")
    dm.SetVolume(gameState.music, 0.3)
}

ResetGame :: proc() {
    gameState.gameBegun = false

    for &hole, i in gameState.holes {
        hole.state = .Dormant
    }

    gameState.flipAvailble = false
    gameState.flipActive = false

    gameState.saltParticles.gravity.y = -abs(gameState.saltParticles.gravity.y)

    // dm.StopSound(gameState.music)

    sa.clear(&gameState.salts)
}

StartGame :: proc() {
    gameState.gameBegun = true
    gameState.timeLeft = GameTime
    gameState.score = 0

    gameState.flipTimer = FlipInterval

    dm.PlaySound(gameState.music)
}

DifficultyCurve :: proc() -> f32{
    // https://www.desmos.com/calculator/at0vzlq4ep
    maxPoint :: 0.9
    maxValue :: 0.2
    curv :: 0.8

    t := 1 - (gameState.timeLeft / GameTime)

    if t > maxPoint {
        return maxValue
    }

    curvature: f32 = (maxValue - 1) / math.pow(f32(maxPoint), curv)
    return curvature * math.pow(t, curv) + 1
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
            dm.PlaySound(cast(dm.SoundHandle) dm.GetAsset("unclick.wav"))
            pressed^ = false
            return inBounds
        }
    }

    if mouseBtn == .JustPressed {
        if inBounds {
            dm.PlaySound(cast(dm.SoundHandle) dm.GetAsset("click.wav"))
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
        dm.StopSound(gameState.music)
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

                gameState.score += 10 * (2 if gameState.flipActive else 1)

                dm.SpawnParticles(&gameState.saltParticles, 20, 
                    atPosition = hole.targetPos + {0, 0.3},
                    additionalSpeed = cast(v2) glsl.normalize(s.end - s.start) * 5
                )

                idx := rand.uint32() % len(HitSoundsNames)
                sound := cast(dm.SoundHandle) dm.GetAsset(fmt.tprintf("hit %v", idx))
                // fmt.println(idx, sound)

                camSize := dm.GetCameraSize(dm.renderCtx.camera)

                dm.SetPan(sound, hole.targetPos.x / camSize.x * (gameState.flipActive ? -1 : 1))
                dm.SetVolume(sound, 0.4)
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

            gameState.flipAnimActive = true
            gameState.flipAnimTimer = 0
            gameState.flipAnimDir = 1

            gameState.saltParticles.gravity.y = abs(gameState.saltParticles.gravity.y)
        }
    }
    else {
        gameState.flipTimer -= dm.time.deltaTime
        if gameState.flipTimer < 0 {
            if gameState.flipActive {
                gameState.flipActive = false
                gameState.flipTimer = FlipInterval

                gameState.flipAnimActive = true
                gameState.flipAnimTimer = 0
                gameState.flipAnimDir = -1

                gameState.saltParticles.gravity.y = -abs(gameState.saltParticles.gravity.y)
            }
            else {
                gameState.flipAvailble = true
            }
        }
    }

    if gameState.flipAnimActive {
        gameState.flipAnimTimer += dm.time.deltaTime
        if gameState.flipAnimTimer >= FlipAnimTime {
            gameState.flipAnimActive = false
            gameState.flipAnimTimer = FlipAnimTime
        }

        p := gameState.flipAnimTimer / FlipAnimTime
        if gameState.flipAnimDir == 1 {
            dm.renderCtx.camera.rotation = p * 180
        }
        else {
            dm.renderCtx.camera.rotation = (1 - p) * 180
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

    dm.DrawTextCentered(fmt.tprintf("%5v", gameState.score), {-1.5, 3.15}, gameState.font, fontSize = 0.9)
    dm.DrawTextCentered(fmt.tprintf("%5.2f",gameState.timeLeft), {1.5, 3.15}, gameState.font, fontSize = 0.9)


    nonPressedOffset :: v2{0, 0.2}
    pressedOffset:: v2{0, 0.23}

    dm.DrawTextCentered(
        "START", 
        StartButtonPos + (gameState.startBtnPressed ? pressedOffset : nonPressedOffset),
        gameState.font, 
        fontSize = 0.25
    )

    flipPressed := gameState.flipBtnPressed || gameState.flipAvailble == false
    dm.DrawTextCentered(
        "FLIP",
        FlipButtonPos + (flipPressed ? pressedOffset : nonPressedOffset),
        gameState.font,
        fontSize = 0.25
    )

    for i in 0..<gameState.salts.len {
        s := &gameState.salts.data[i]
        dm.DrawSprite(gameState.saltSprite, s.position, rotation = s.rotation)
    }

    dm.UpdateAndDrawParticleSystem(&gameState.saltParticles)

    // dm.DrawGrid()
}