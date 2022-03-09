require fio
require daslib/media
require daslib/decs_boost
//options debugger            // uncomment for debug in VS Code
//require daslib/debug        // uncomment for debug in VS Code


var textures: table<string; ImageHandle>


struct SpriteSheet
    texture_id: string
    vertical_num: int
    frame_width: int
    frame_height: int


var spritesheets: table<string; SpriteSheet?>


struct MapBlock
    spritesheet_id : string
    sprite_index : int

    solid: bool
    platform: bool
    breakable: bool
    hit_points: int


var map: array<array<MapBlock?>>

var view_position: float2
var map_size: int2
var debug_text : float


let 
    BLOCK_SIZE = 16.0
    BACK_SIZE = 40.0
    PIXEL_SCALE = 3.0

var
    RAND_SEED = random_seed(0)

[decs_template]
struct CmpTransform
    position: float2


[decs_template]
struct CmpSprite
    spritesheet_id : string
    index: int
    scale: float2
    anchor: float2
    angle: float

    anim_frames: table<string; array<int>?>?
    anim_speed: table<string; float>
    anim_index: float
    anim_current: string
    anim_active: bool
    anim_loop : bool

    visible: bool


[decs_template]
struct CmpPhysics
    size: float
    gravity: float
    fly_mode: bool

    velocity: float2 
    on_ground: bool

    movement: float2
    hit_force : float2

    acc_speed: float
    max_speed: float
    friction: float
    jump_speed: float


[decs_template]
struct CmpCamera
    follow_player: bool
    border: float2


[decs_template]
struct CmpPlayerControlled
    player_id: int


[decs_template]
struct CmpHealth
    hp : float
    hit_cooldown : float
    dead : bool


enum AIType
    None
    Walker
    Slime
    Bat 
    BigGuy


[decs_template]
struct CmpAIControlled
    ai_type: AIType
    timer: table<string; float>
    state: string
    

def add_spritesheet(var id: string; var file_name: string; frame_width: int; frame_height: int)
    let tid = length(textures)

    textures[id] <- create_managed_image(file_name)

    spritesheets[id] := new [[SpriteSheet texture_id = id,
                                frame_width = frame_width,
                                frame_height = frame_height,
                                vertical_num = textures[id].width / frame_width]]


def new_mapblock(var spritesheet_id: string; sprite_index: int; solid: bool; platform: bool; breakable: bool; hit_points: int)
    var mb = new [[MapBlock spritesheet_id = spritesheet_id, sprite_index = sprite_index,
                solid = solid, platform = platform, breakable = breakable, hit_points = hit_points]]
    return <- mb


def get_block(point: float2) : MapBlock?
    var p = int2(point.x / BLOCK_SIZE, point.y / BLOCK_SIZE)

    if p.y < 0
        return null
    
    if p.x < 0
        return null

    if p.y >= length(map)
        return null
    
    if p.x >= length(map[p.y])
        return null
    
    return map[p.y][p.x]
        


def draw_sprite(var spritesheet_id: string; index: int; scale: float2; anchor: float2; angle: float; position: float2; debug_text: string const implicit)
    
    let ss := spritesheets[spritesheet_id]
    
    let rect = float4(float(ss.frame_width * (index % ss.vertical_num)),
                    float(ss.frame_height * (index / ss.vertical_num)),
                    float(ss.frame_width),
                    float(ss.frame_height))

    let draw_scale = float2(float(ss.frame_width) * scale.x, float(ss.frame_height) * scale.y) * PIXEL_SCALE
    let m_angle = angle / 180.0 * PI

    var xx = (0.5 - anchor.x) * float(ss.frame_width)
    var yy = (0.5 - anchor.y) * float(ss.frame_height)
    
    var px =  xx * cos(m_angle) - yy * sin(m_angle)
    var py =  xx * sin(m_angle) + yy * cos(m_angle)
    
    textures[ss.texture_id] |> draw_image_transformed((floor(position.x) + px) * PIXEL_SCALE,
                                                        (floor(position.y) + py) * PIXEL_SCALE,
                                                        rect, make_color(1.0), draw_scale, m_angle)
    
    if debug_text != ""
        text_out((floor(position.x) + px) * PIXEL_SCALE,                                 
                (floor(position.y) + py) * PIXEL_SCALE,
                "{debug_text}", 0xFFF0F0F0)


def animation_play(eid: EntityId; var name: string; loop: bool; reset: bool)
    query(eid) <| $(var sprite: CmpSprite)
        if reset
            sprite.anim_index = 0.0
        sprite.anim_current = name
        sprite.anim_active = true
        sprite.anim_loop = loop


def make_camera(x, y: float; border: float2)
    view_position = float2(0, 0)

    create_entity <| @ ( eid, cmp ) 
        cmp |> set("eid", eid)
        cmp |> apply_decs_template([[CmpTransform position = float2(x, y)]])
        cmp |> apply_decs_template([[CmpCamera follow_player = true, border = border]])


def make_enemy(ai_type: AIType; x, y: float)
    
    create_entity <| @ ( eid, cmp ) 

        var hp = 0.0
        var spritesheet_id = ""

        var anim_frames : table<string; array<int>?>?
        var anim_speed : table<string; float>

        cmp |> set("eid", eid)
        cmp |> apply_decs_template([[CmpTransform position = float2(x, y)]])
        
        if ai_type == AIType Walker
            spritesheet_id = "walker"
            
            anim_frames := new {{
                "walk" => new [{int 0; 1}]}}
            anim_speed := {{
                "walk" => 0.1}}

            cmp |> apply_decs_template([[CmpAIControlled ai_type = ai_type, state = "walk_left"]]) 
            cmp |> apply_decs_template([[CmpPhysics size = 16.0, fly_mode = false, gravity = 162.0,
                acc_speed = 300.0, friction = -4.8, max_speed = 40.0, jump_speed = 0.0]])
            hp = 2.0

        elif ai_type == AIType Bat
            spritesheet_id = "bat"

            anim_frames := new {{
                "fly" => new [{int 0; 1; 2}] }}
            anim_speed := {{
                "fly" => 0.1 }}

            cmp |> apply_decs_template([[CmpAIControlled ai_type = ai_type, state = "fly", timer <- {{"new_dir" => 0.0}}]]) 
            cmp |> apply_decs_template([[CmpPhysics size = 16.0, fly_mode = true,
                acc_speed = 600.0, friction = 0.0, max_speed = 30.0]])
            hp = 1.0

        elif ai_type == AIType Slime
            spritesheet_id = "slime"

            anim_frames := new {{
                "idle" => new [{int 0; 1}]; 
                "jump_up" => new [{int 5}]; 
                "jump_down" => new [{int 6}] }}
                
            anim_speed := {{
                "idle" => 0.0; 
                "jump_up" => 0.0; 
                "jump_down" => 0.0 }}

            cmp |> apply_decs_template([[CmpAIControlled ai_type = ai_type, state = "idle", timer <- {{"jump_cooldown" => 0.0}}]]) 
            cmp |> apply_decs_template([[CmpPhysics size = 16.0, fly_mode = false, gravity = 162.0,
                acc_speed = 300.0, friction = -4.8, max_speed = 40.0, jump_speed = 130.0]])
            hp = 1.0

        cmp |> apply_decs_template([[CmpSprite spritesheet_id = spritesheet_id, index = 0,
            scale = float2(1.0, 1.0), anchor = float2(0.5, 0.5), angle = 0.0, visible = true,
            anim_frames := anim_frames,
            anim_speed := anim_speed
        ]]) 
        cmp |> apply_decs_template([[CmpHealth hp = hp, hit_cooldown = 0.0, dead = false]])

def make_player(id: int; x, y: float)

    create_entity <| @ ( eid, cmp ) 
        cmp |> set("eid", eid)
        cmp |> apply_decs_template([[CmpTransform position = float2(x, y)]])
        cmp |> apply_decs_template([[CmpPlayerControlled player_id = id]])
        cmp |> apply_decs_template([[CmpPhysics size=16.0, fly_mode = false, gravity = 162.0, acc_speed = 600.0, 
                                        friction = -4.8, max_speed = 80.0, jump_speed = 130.0]])
        cmp |> apply_decs_template([[CmpSprite spritesheet_id = "player", index = 0, scale = float2(1.0, 1.0), anchor = float2(0.5, 0.5), angle = 0.0, visible = true,
        
            anim_frames := new {{
                "idle" => new [{int 0}]; 
                "jump" => new [{int 1}]; 
                "walk" => new [{int 4; 5; 6; 7}] }},
                
            anim_speed := {{
                "idle" => 0.0; 
                "jump" => 0.0; 
                "walk" => 0.2 }}
        ]]) 
        cmp |> apply_decs_template([[CmpHealth hp = 5.0, hit_cooldown = 0.0, dead = false]])

        

// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize
    restart()

    set_window_title("Sample Game Platormer")

    add_spritesheet("tiles1", "tiles.png", 16, 16)
    add_spritesheet("back", "back.png", int(BACK_SIZE), int(BACK_SIZE))
    add_spritesheet("player", "player.png", 16, 16)
    add_spritesheet("walker", "walker.png", 16, 16)
    add_spritesheet("slime", "slime.png", 16, 16)
    add_spritesheet("bat", "bat.png", 16, 16)


    let fworld = fopen("world.txt", "rb")
    let ss = fread(fworld) + "\n"
    
    var a: array<MapBlock?>
    
    map_size = int2(0, 0)
    var y = 0 
    var x = 0

    for ch in ss
        var block_center = float2((float(x) + 0.5) * BLOCK_SIZE, (float(y) + 0.5) * BLOCK_SIZE)
        
        if ch == '\n'
            x = -1 
            y += 1
            map |> emplace(a)
            a |> clear

        elif ch == '\r'
            pass

        elif ch >= '0' && ch < '8'
            a |> emplace(new_mapblock("tiles1", ch - int('0'), true, false, false, 0))

        elif ch == '_'
            a |> emplace(new_mapblock("tiles1", 10, true, true, false, 0))

        elif ch == 'P'
            make_player(0, block_center.x, block_center.y)
            a |> push(null)
            commit()

        elif ch == 'W'
            make_enemy(AIType Walker, block_center.x, block_center.y)
            a |> push(null)
            commit()

        elif ch == 'S'
            make_enemy(AIType Slime, block_center.x, block_center.y)
            a |> push(null)
            commit()
            
        elif ch == 'B'
            make_enemy(AIType Bat, block_center.x, block_center.y)
            a |> push(null)
            commit()

        else
            a |> push(null)
        
        x+=1

        if x > map_size.x
            map_size.x = x

        if y > map_size.y
            map_size.y = y 
        
    make_camera(0.0, 0.0, float2(float(map_size.x) * BLOCK_SIZE, float(map_size.y) * BLOCK_SIZE))
    commit()



[decs(stage = update_actions)]
def update_player_input(var player: CmpPlayerControlled; var phys: CmpPhysics; var sprite: CmpSprite; eid: EntityId)
    let left_move = get_key(VK_LEFT) ? -1.0 : 0.0
    let right_move = get_key(VK_RIGHT) ? 1.0 : 0.0
    let jump = get_key(VK_UP) ? 1.0 : 0.0
    let down = get_key_down(VK_DOWN) ? -1.0 : 0.0

    let vertical_move = left_move + right_move

    if vertical_move != 0.0
        if phys.on_ground
            animation_play(eid, "walk", true, false)
        else
            animation_play(eid, "jump", true, false)
    else
        animation_play(eid, "idle", true, false)

    if vertical_move > 0.0
        sprite.scale = float2(1,1)
    if vertical_move < 0.0
        sprite.scale = float2(-1,1)

    phys.movement = float2(vertical_move, jump + down)   


[decs(stage = update_actions)]
def update_enemy_ai(var ai: CmpAIControlled; var transform: CmpTransform; var phys: CmpPhysics; var sprite: CmpSprite; eid: EntityId)
    let dt = get_delta_time()

    for k in keys(ai.timer)
        ai.timer[k] -= dt

    var player_distance = FLT_MAX
    var player_position = float2(0, 0)
    var player_found = false

    query <| $ (pl_controlled: CmpPlayerControlled; pl_transform: CmpTransform)
        player_position = pl_transform.position
        player_distance = length(player_position - transform.position)
        player_found = true

    if ai.ai_type == AIType Walker
        animation_play(eid, "walk", true, false)

        var dir = ai.state == "walk_left" ? -1.0 : 1.0
        var next_block = get_block(float2(transform.position.x + BLOCK_SIZE * 0.6 * dir, transform.position.y))
        var next_block_below = get_block(float2(transform.position.x + BLOCK_SIZE * 0.6 * dir, transform.position.y + BLOCK_SIZE))

        if next_block != null || (next_block == null && next_block_below == null)
            dir = -dir
            if ai.state == "walk_left"
                ai.state = "walk_right"
            else
                ai.state = "walk_left"
    
        phys.movement = float2(dir, 0.0)  
        sprite.scale.x = dir
            
    elif ai.ai_type == AIType Bat
        animation_play(eid, "fly", true, false)

        debug_text = ai.timer["new_dir"]
        
        if ai.timer["new_dir"] <= 0.0

            var new_dir = float2(2.0*random_float(RAND_SEED)-1.0, 2.0*random_float(RAND_SEED)-1.0) 
            new_dir = normalize(new_dir)

            phys.movement = new_dir
            ai.timer["new_dir"] = 0.5

    elif ai.ai_type == AIType Slime

        var dir = 1.0
        var next_block = get_block(float2(transform.position.x + BLOCK_SIZE * 0.6 * dir, transform.position.y))
        if next_block != null
            dir = -1.0

        if player_found && player_distance < BLOCK_SIZE * 5.0
            dir = transform.position.x > player_position.x ? -1.0 : 1.0

        if ai.state == "idle"
            animation_play(eid, "idle", true, false)
            if ai.timer["jump_cooldown"] <= 0.0 && phys.on_ground
                phys.movement = float2(dir, 1.0) 
                ai.state = "jumping"
            else
                phys.movement = float2(0.0, 0.0)  
            
        elif ai.state == "jumping"
            animation_play(eid, phys.velocity.y < 0.0 ? "jump_up" : "jump_down", true, false)
            
            if phys.on_ground
                ai.state = "idle"
                ai.timer["jump_cooldown"] = 3.0

            phys.movement.y = 0.0
            
        sprite.scale.x = dir


[decs(stage = update_collisions)]
def update_player_enemies_collisions(var ai: CmpAIControlled; var health: CmpHealth; var phys: CmpPhysics; var transform: CmpTransform)

    query <| $ (pl_controlled: CmpPlayerControlled; var pl_health: CmpHealth; var pl_phys: CmpPhysics; pl_transform: CmpTransform)
        if pl_health.hit_cooldown <= 0.0
            if length(pl_transform.position - transform.position) <= 0.8 * phys.size / 2.0 + 0.8 * pl_phys.size / 2.0
                pl_health.hp -= 1.0
                pl_health.hit_cooldown = 1.0
                pl_phys.hit_force = pl_transform.position - transform.position


[decs(stage = update_physics)]
def update_physics(var phys: CmpPhysics; var transform: CmpTransform)
    let dt = get_delta_time()

    var acc_x = 0.0
    var acc_y = 0.0

    var skip_platform = false


    var hit_acc = normalize(phys.hit_force) * 300.0
    hit_acc.y = 0.33 * hit_acc.y
    phys.velocity += hit_acc

    if phys.fly_mode
        acc_x = phys.movement.x * phys.acc_speed
        acc_y = phys.movement.y * phys.acc_speed
        phys.velocity.x += acc_x * dt
        phys.velocity.y += acc_y * dt
        phys.velocity.x = clamp(phys.velocity.x, -phys.max_speed, phys.max_speed)
        phys.velocity.y = clamp(phys.velocity.y, -phys.max_speed, phys.max_speed)
        skip_platform = true

    else
        acc_x = phys.movement.x * phys.acc_speed
        acc_x += phys.velocity.x * phys.friction
        phys.velocity.x += acc_x * dt

        phys.velocity.x = clamp(phys.velocity.x, -phys.max_speed, phys.max_speed)

        phys.velocity.y += phys.gravity * dt

        if phys.on_ground 
            if phys.movement.y > 0.0
                phys.velocity.y -= phys.jump_speed
        
        if phys.movement.y < 0.0
            skip_platform = true
        
        acc_y = phys.gravity

    var dx = phys.velocity.x * dt + acc_x * 0.5 * dt * dt
    var dy = phys.velocity.y * dt + acc_y * 0.5 * dt * dt

    if (dx != 0.0)
        var dir_x = dx > 0.0 ? 1.0 : -1.0

        let collision_pos_x = transform.position.x + dx + dir_x * phys.size * 0.5

        let col_block = get_block(float2(collision_pos_x, transform.position.y))
        let col_block_cx = BLOCK_SIZE * (0.5 + float(int(collision_pos_x / BLOCK_SIZE)))

        let empty_space = col_block == null 

        if empty_space || col_block.platform
            transform.position.x += dx 
        else
            transform.position.x = col_block_cx - (BLOCK_SIZE + phys.size) * 0.5 * dir_x
            phys.velocity.x = 0.0

    if (dy != 0.0)
        var dir_y = dy > 0.0 ? 1.0 : -1.0

        let collision_pos_y = transform.position.y + dy + dir_y * phys.size * 0.5

        var col_block_left = get_block(float2(transform.position.x-phys.size*0.4, collision_pos_y))
        var col_block_right = get_block(float2(transform.position.x+phys.size*0.4, collision_pos_y))

        let col_block_cy = BLOCK_SIZE * (0.5 + float(int(collision_pos_y / BLOCK_SIZE)))
        
        let empty_space = col_block_left == null && col_block_right == null

        let platform_left = col_block_left != null && col_block_left.platform
        let platform_right = col_block_right != null && col_block_right.platform

        let platform_collision = (platform_left && platform_right) || (platform_left && col_block_right == null) || (platform_right && col_block_left == null)

        let below_platform = transform.position.y + phys.size * 0.5 > col_block_cy - BLOCK_SIZE * 0.5


        if empty_space || (platform_collision && (skip_platform || dir_y < 0.0 || (dir_y > 0.0 && below_platform)))
            transform.position.y += dy
            phys.on_ground = false
        else
            transform.position.y = col_block_cy - (BLOCK_SIZE + phys.size) * 0.5 * dir_y
            phys.velocity.y = 0.0

            if dir_y > 0.0
                phys.on_ground = true
            else
                phys.on_ground = false
    phys.hit_force = float2(0.0, 0.0)


[decs(stage = update_camera)]
def update_camera(var cam: CmpCamera; var transform: CmpTransform)
    var cam_width = float(get_screen_width()) / PIXEL_SCALE
    var cam_height = float(get_screen_height()) / PIXEL_SCALE

    if cam.follow_player
        query <| $ (pl_controlled: CmpPlayerControlled; pl_transform: CmpTransform)
            transform.position = pl_transform.position - float2(cam_width, cam_height) / 2.0

        transform.position.x = clamp(transform.position.x, 0.0, cam.border.x - cam_width)
        transform.position.y = clamp(transform.position.y, 0.0, cam.border.y - cam_height)
    
    view_position = -transform.position


[decs(stage = update_animations)]
def update_animations(var sprite: CmpSprite)
    let dt = get_delta_time()

    if sprite.anim_active
        debug(sprite.anim_frames)
        sprite.anim_index += sprite.anim_speed[sprite.anim_current] * dt * 60.0
        let total = length(*(*sprite.anim_frames)[sprite.anim_current])
        let frame = int(sprite.anim_index) % total

        if !sprite.anim_loop && frame >= total
            sprite.anim_active = false
        else
            sprite.index = (*(*sprite.anim_frames)[sprite.anim_current])[frame]


[decs(stage = post_update)]
def update_health(var health: CmpHealth; var sprite: CmpSprite; eid: EntityId)
    let dt = get_delta_time()

    if health.hp <= 0.0
        health.dead = true

    if health.hit_cooldown > 0.0
        sprite.visible = int(health.hit_cooldown * 20.0) % 2 == 0
        health.hit_cooldown -= dt
    else
        sprite.visible = true
        if health.hp <= 0.0
            delete_entity(eid)


[decs(stage = draw_entities)]
def draw_entities(var sprite: CmpSprite; var transform: CmpTransform)
    if sprite.visible
        var txt = ""

        draw_sprite(sprite.spritesheet_id, sprite.index, sprite.scale, sprite.anchor, sprite.angle,
            float2(view_position.x + transform.position.x, view_position.y + transform.position.y), sprite.anim_active ? "{sprite.anim_current} {(*sprite.anim_frames)[sprite.anim_current]}" : "")

            


def draw_back()
    let back_offset_x = view_position.x * 0.8
    for y in range(20)
        for x in range(20)
            draw_sprite("back", 0, float2(1.0, 1.0), float2(0.0, 0.0), 0.0,
                float2(back_offset_x + float(x) * BACK_SIZE, float(y) * BACK_SIZE), "")
            

def draw_tiles()
    for y in range(length(map))
        for x in range(length(map[y]))
            if map[y][x] != null
                draw_sprite(map[y][x].spritesheet_id, map[y][x].sprite_index, float2(1.0, 1.0), float2(0.0, 0.0), 0.0,
                    float2(view_position.x + float(x) * BLOCK_SIZE, view_position.y + float(y) * BLOCK_SIZE), "")


// this function is called to update game data,
// dt - time elapsed since the previous update (in seconds)
[export]
def act(dt: float)
    decs_stage("update_actions")
    commit()

    decs_stage("update_collisions")
    commit()

    decs_stage("update_physics")
    commit()

    decs_stage("update_animations")
    commit()

    decs_stage("update_camera")
    commit()

    decs_stage("post_update")
    commit()

    if get_key(VK_ESCAPE)
        schedule_quit_game()


// this function will be called every frame after 'act',
// you can draw anything in this function
[export]
def draw


    
    draw_back()

    enable_alpha_blend()

    draw_tiles()

    //text_out(100,80, "test {debug_text}", 0xFFF0F0F0)
    decs_stage("draw_entities")
    commit()

    //text_out(5, 5, ss,make_color(1.0))

