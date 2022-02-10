require fio
require daslib/media
require daslib/decs_boost
//options debugger            // uncomment for debug in VS Code
//require daslib/debug        // uncomment for debug in VS Code


var textures: table<string;ImageHandle>

struct SpriteSheet
    texture_id : string
    vertical_num : int
    frame_width : float
    frame_height : float

var spritesheets: table<string;SpriteSheet?>




struct Sprite
    spritesheet : SpriteSheet?
    index : int
    scale : float2
    anchor : float2
    angle : float


    anim_frames : table<string;array<int>?>
    anim_speed : table<string;float>
    anim_index : float
    anim_current : string
    anim_active : bool




struct MapBlock
    sprite : Sprite?
    solid : bool
    platform : bool
    breakable: bool
    hit_points : int

var map : array<array<MapBlock?>>
var back : Sprite?
var camera_offset :float2
var map_size : int2

let 
    BLOCK_SIZE = 16.0
    BACK_SIZE = 40.0
    PIXEL_SCALE = 3.0
    CURRENT_PLAYER_ID = 0



[decs_template]
struct CmpTransform
    position:float2

[decs_template]
struct CmpDraw
    sprite:Sprite?



[decs_template]
struct CmpPhysics

    size:float
    gravity:float
    fly_type:bool

    velocity:float2 
    on_ground:bool

    movement:float2

    acc_speed:float
    max_speed:float
    friction:float
    jump_speed:float


    
[decs_template]
struct CmpCamera
    follow_player:bool
    border:float2

[decs_template]
struct CmpPlayerControlled
    player_id : int
    

enum AIType
    None
    Walker
    Slime
    Bat 
    BigGuy


[decs_template]
struct CmpAIControlled
    ai_type : AIType
    timer : table<string;float>
    state:string
    




def add_spritesheet(id,file_name,frame_width,frame_height)

    
    let tid = length(textures)

    textures[id] <- create_managed_image(file_name)

    spritesheets[id] := new [[SpriteSheet texture_id =id, frame_width=float(frame_width),frame_height=float(frame_height),vertical_num = textures[id].width/frame_width]]




def new_mapblock(spritesheet,texture_index,angle,solid,platform,breakable,hit_points)

    var mb =new [[MapBlock sprite <- new_sprite(spritesheet,texture_index,float2(0.0,0.0)),
            solid = solid, platform = platform,breakable = breakable,hit_points = hit_points]]
    mb.sprite.angle = angle
    return <- mb


def get_block(point) : MapBlock?

    var p = int2(point.x/BLOCK_SIZE,point.y/BLOCK_SIZE)

    if (p.y<0)
        return null
    
    if (p.x<0)
        return null

    if (p.y>=length(map))
        return null
    
    if (p.x>=length(map[p.y]))
        return null
    
    return map[p.y][p.x]
        

def new_sprite(spritesheet_id,start_index,anchor)
    return <- new [[Sprite spritesheet:=spritesheets[spritesheet_id],index=start_index,scale=float2(1.0,1.0),anchor=anchor,angle=0.0,
            anim_active = false, anim_index = 0.0,anim_current=""]]

def draw(var sprite: Sprite; x:float; y:float)


    
    let ss := sprite.spritesheet
    let rect = float4(ss.frame_width*float(sprite.index % ss.vertical_num),ss.frame_height*float(sprite.index / ss.vertical_num),ss.frame_width,ss.frame_height)
    let scale = float2(ss.frame_width*sprite.scale.x,ss.frame_height*sprite.scale.y)*PIXEL_SCALE
    let m_angle = sprite.angle/180.0*PI

    
    var xx = (0.5 - sprite.anchor.x)*ss.frame_width
    var yy = (0.5 - sprite.anchor.y)*ss.frame_height
    
    var px =  xx * cos(m_angle) - yy * sin(m_angle)
    var py =  xx * sin(m_angle) + yy * cos(m_angle)

    
    textures[ss.texture_id] |> draw_image_transformed(
         (x+px) * PIXEL_SCALE,
         (y+py) * PIXEL_SCALE,
         rect, make_color(1.0),
          scale,m_angle)


    return


def update(var sprite: Sprite; dt : float)

    
    if sprite.anim_active
        sprite.anim_index+=sprite.anim_speed[sprite.anim_current]*dt*60.0
        sprite.index = (*sprite.anim_frames[sprite.anim_current])[int(sprite.anim_index) % length(*sprite.anim_frames[sprite.anim_current]) ]


    return 
    

def add_animation(var sprite:Sprite;name:string; frames:array<int>?; speed:float)
    sprite.anim_frames[name] := frames
    sprite.anim_speed[name] = speed

def animation_play(var sprite:Sprite;name:string; reset:bool)
    if reset
        sprite.anim_index = 0.0
    sprite.anim_current = name
    sprite.anim_active = true

def animation_stop(var sprite:Sprite)
    sprite.anim_active = false




def set_index(var sprite:Sprite; index:int)
    sprite.index = index




def make_camera(x,y,border)

    camera_offset = float2(0,0)



    create_entity <| @ ( eid, cmp ) 
        cmp |> set("eid", eid)
        cmp |> apply_decs_template([[CmpTransform position = float2(x,y)]])
        cmp |> apply_decs_template([[CmpCamera follow_player = true,border = border]])


def make_enemy(var ai_type: AIType;var x,y : float)


    var spr : Sprite?
    var phys : CmpPhysics

    if ai_type==AIType Walker
        spr = new_sprite("walker",0,float2(0.5,0.5))
        *spr |> add_animation("walk",new [{int 0;1}],0.1)
        phys = [[CmpPhysics size=16.0, fly_type=false, gravity = 162.0, acc_speed=300.0,friction=-4.8, max_speed=40.0,jump_speed=40.0]]
        
    elif ai_type==AIType Bat
        spr = new_sprite("bat",0,float2(0.5,0.5))
        *spr |> add_animation("fly",new [{int 0;1;2}],0.1)
        phys = [[CmpPhysics size=16.0, fly_type=true, acc_speed=600.0,friction=-4.8, max_speed=80.0]]
    elif ai_type==AIType Slime
        spr = new_sprite("slime",0,float2(0.5,0.5))
        *spr |> add_animation("idle",new [{int 0;1}],0.1)
        phys = [[CmpPhysics size=16.0, fly_type=false, gravity = 162.0, acc_speed=300.0,friction=-4.8, max_speed=40.0,jump_speed=130.0]]


    create_entity <| @ ( eid, cmp ) 
        cmp |> set("eid", eid)
        cmp |> apply_decs_template([[CmpTransform position = float2(x,y)]])
        cmp |> apply_decs_template([[CmpDraw sprite= spr]]) 
        cmp |> apply_decs_template(phys)
        cmp |> apply_decs_template([[CmpAIControlled ai_type = ai_type]]) 
        

def make_player(id,x,y)


    var spr  = new_sprite("player",0,float2(0.5,0.5))

    *spr |> add_animation("idle",new [{int 0}],0.0)
    *spr |> add_animation("jump",new [{int 1}],0.0)
    *spr |> add_animation("walk",new [{int 4;5;6;7}],0.2)

    create_entity <| @ ( eid, cmp ) 
        cmp |> set("eid", eid)
        cmp |> apply_decs_template([[CmpTransform position = float2(x,y)]])
        cmp |> apply_decs_template([[CmpPlayerControlled player_id = CURRENT_PLAYER_ID]])
        cmp |> apply_decs_template([[CmpPhysics size=16.0, fly_type=false, gravity = 162.0, acc_speed=600.0,friction=-4.8, max_speed=80.0,jump_speed=130.0]])
        cmp |> apply_decs_template([[CmpDraw sprite = spr]]) 
        



// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize


    restart()

    set_window_title("Sample Game Platormer")

    

    add_spritesheet("tiles1","tiles.png",16,16)
    add_spritesheet("back","back.png",int(BACK_SIZE),int(BACK_SIZE))
    add_spritesheet("player","player.png",16,16)
    add_spritesheet("walker","walker.png",16,16)
    add_spritesheet("slime","slime.png",16,16)
    add_spritesheet("bat","bat.png",16,16)

    back := new_sprite("back",0,float2(0,0))

    let fworld = fopen("world.txt", "rb")
    let ss = fread(fworld)+"\n"
    
    var a : array<MapBlock?>
    
    map_size = int2(0,0)
    var y = 0 
    var x = 0


    for ch in ss


        var block_center = float2((float(x)+0.5)*BLOCK_SIZE,(float(y)+0.5)*BLOCK_SIZE)
        
        if ch=='\n'
            x = -1 
            y+=1
            map |> emplace(a)
            a |> clear
        elif ch=='\r'
            pass
        elif ch>='0' && ch<'8'
            a |> emplace(new_mapblock("tiles1",ch-int('0'),0.0,true,false,false,0))
        elif ch=='_'
            a |> emplace(new_mapblock("tiles1",10,0.0,true,true,false,0))
        elif ch=='P'
            make_player(0,block_center.x,block_center.y)
            a |> push(null)
            commit()
        elif ch=='W'
            make_enemy(AIType Walker,block_center.x,block_center.y)
            a |> push(null)
            commit()
        elif ch=='S'
            make_enemy(AIType Slime,block_center.x,block_center.y)
            a |> push(null)
            commit()
        elif ch=='B'
            make_enemy(AIType Bat,block_center.x,block_center.y)
            a |> push(null)
            commit()
        else
            a |> push(null)
        
        x+=1


        if x>map_size.x
            map_size.x = x
        if y>map_size.y
            map_size.y = y 
        


    make_camera(0,0,float2(float(map_size.x)*BLOCK_SIZE,float(map_size.y)*BLOCK_SIZE))
    

    commit()
    decs_stage("init_ai")
    commit()



[decs(stage = update_actions)]
def update_player_input(var player_controlled: CmpPlayerControlled; var player_physics: CmpPhysics;var draw: CmpDraw;  eid: EntityId)

    let left_move = get_key(VK_LEFT) ? -1.0 : 0.0
    let right_move = get_key(VK_RIGHT) ? 1.0 : 0.0
    let jump =  get_key(VK_UP) ? 1.0 : 0.0
    let down =  get_key_down(VK_DOWN) ? -1.0 : 0.0


    let vertical_move = left_move+right_move

    if vertical_move!=0.0
        if player_physics.on_ground
            *draw.sprite |> animation_play("walk",false)
        else
            *draw.sprite |> animation_play("jump",false)
    else
        *draw.sprite |> animation_play("idle",false)

    if vertical_move>0.0
        draw.sprite.scale = float2(1,1)
    if vertical_move<0.0
        draw.sprite.scale = float2(-1,1)

    player_physics.movement = float2(vertical_move, jump+down)   



[decs(stage = init_ai)]
def init_ai(var ai: CmpAIControlled;var draw: CmpDraw; eid: EntityId)


    if ai.ai_type==AIType Walker
        ai.state = "walk"
        *draw.sprite |> animation_play("walk",true)
        
        
    elif ai.ai_type==AIType Bat
        ai.state = "fly"
        *draw.sprite |> animation_play("fly",true)

    elif ai.ai_type==AIType Slime
        ai.state = "jump_ready"




[decs(stage = update_actions)]
def update_enemy_ai(var ai: CmpAIControlled; var enemy_physics: CmpPhysics; eid: EntityId)

    enemy_physics.movement = float2(1.0, 1.0)  




[decs(stage = update_physics)]
def update_physics(var entity_physics: CmpPhysics; var entity_transform: CmpTransform; eid: EntityId)

    let dt = get_delta_time()

    var acc_x = entity_physics.movement.x*entity_physics.acc_speed
    acc_x+=entity_physics.velocity.x*entity_physics.friction
    entity_physics.velocity.x+=acc_x*dt

    if entity_physics.velocity.x > entity_physics.max_speed
        entity_physics.velocity.x=entity_physics.max_speed

    
    if entity_physics.velocity.x < -entity_physics.max_speed
        entity_physics.velocity.x=-entity_physics.max_speed



    entity_physics.velocity.y+=entity_physics.gravity * dt

    if entity_physics.on_ground 

        if entity_physics.movement.y>0.0
            entity_physics.velocity.y-=entity_physics.jump_speed
    
    
    var skip_platform = false
    if entity_physics.movement.y<0.0
        skip_platform = true

    var dx = entity_physics.velocity.x*dt + acc_x*0.5*dt*dt
    var dy = entity_physics.velocity.y*dt + entity_physics.gravity*0.5*dt*dt


    if (dx!=0.0)
        var dir_x = dx>0.0 ? 1.0 : -1.0
        

        let collision_pos_x = entity_transform.position.x+dx+dir_x*entity_physics.size*0.5


        let col_block = get_block(float2(collision_pos_x,entity_transform.position.y))
        let col_block_cx = BLOCK_SIZE*(0.5+float(int((collision_pos_x)/BLOCK_SIZE)))

        let empty_block = col_block==null 

        if empty_block || col_block.platform
            entity_transform.position.x+=dx 
        else
            entity_transform.position.x = col_block_cx- (BLOCK_SIZE+entity_physics.size)*0.5*dir_x
            entity_physics.velocity.x = 0.0

    if (dy!=0.0)
        var dir_y = dy>0.0 ? 1.0 : -1.0

        let collision_pos_y = entity_transform.position.y+dy+dir_y*entity_physics.size*0.5

        let col_block = get_block(float2(entity_transform.position.x,collision_pos_y))
        let col_block_cy = BLOCK_SIZE*(0.5+float(int((collision_pos_y)/BLOCK_SIZE)))

        
        let empty_block = col_block==null

        if empty_block || (col_block.platform && (skip_platform || dir_y < 0.0 || (dir_y > 0.0 && entity_transform.position.y+entity_physics.size*0.5>col_block_cy-BLOCK_SIZE*0.5)))
            entity_transform.position.y+=dy
            entity_physics.on_ground = false
        else
            entity_transform.position.y = col_block_cy - (BLOCK_SIZE+entity_physics.size)*0.5*dir_y
            entity_physics.velocity.y = 0.0

            if dir_y>0.0
                entity_physics.on_ground = true
            else
                entity_physics.on_ground = false



    entity_physics.movement = float2(0,0)
    
[decs(stage = update_camera)]
def update_camera(var cam: CmpCamera; var cam_transform: CmpTransform)



    var cam_width = float(get_screen_width())/PIXEL_SCALE
    var cam_height = float(get_screen_height())/PIXEL_SCALE



    if cam.follow_player
        query <| $ (pl_controlled: CmpPlayerControlled; pl_transform: CmpTransform; eid: EntityId)
            cam_transform.position = pl_transform.position-float2(cam_width,cam_height)/2.0

        cam_transform.position.x = clamp(cam_transform.position.x,0.0,cam.border.x-cam_width)
        cam_transform.position.y = clamp(cam_transform.position.y,0.0,cam.border.y-cam_height)
    

    camera_offset = -cam_transform.position





def draw_back()
    let back_offset_x = camera_offset.x*0.8
    for y in range(20)
        for x in range(20)
            *back |> draw(back_offset_x+float(x)*BACK_SIZE,float(y)*BACK_SIZE)
            



def draw_tiles()
    for y in range(length(map))
        for x in range(length(map[y]))
            if map[y][x]!=null
                *map[y][x].sprite |> draw(camera_offset.x+float(x)*BLOCK_SIZE,camera_offset.y+float(y)*BLOCK_SIZE)


[decs(stage = update_animations)]
def update_animations(var entity_draw: CmpDraw; eid: EntityId)

    let dt = get_delta_time()

    *entity_draw.sprite |> update(dt)



[decs(stage = draw_entities)]
def draw_entities(var entity_draw: CmpDraw; var entity_transform: CmpTransform; eid: EntityId)


    //entity_draw.sprite.angle+=0.1

    *entity_draw.sprite |> draw(camera_offset.x+entity_transform.position.x,camera_offset.y+entity_transform.position.y)



    return


// this function is called to update game data,
// dt - time elapsed since the previous update (in seconds)
[export]
def act(dt: float)

    decs_stage("update_actions")
    commit()


    decs_stage("update_physics")
    commit()

    decs_stage("update_animations")
    commit()

    
    decs_stage("update_camera")
    commit()

    if get_key(VK_ESCAPE)
        schedule_quit_game()
    return

// this function will be called every frame after 'act',
// you can draw anything in this function
[export]
def draw




    draw_back()
    //commit()
    enable_alpha_blend()
    draw_tiles()
    //commit()


    //text_out(100,80, "test {spritesheets["back"]}", 0xFFF0F0F0)
    //text_out(100,100, "test {spritesheets["tiles1"]}", 0xFFF0F0F0)
    decs_stage("draw_entities")
    commit()



    
     


    //text_out(5, 5, ss,make_color(1.0))

    return
