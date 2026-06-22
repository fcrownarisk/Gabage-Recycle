import std/[math, random, os, times, strformat, json, sequtils, tables, strutils, asyncdispatch, asyncnet, base64, sha1, uri]
import opengl, glfw3, stb_image/read as stbi

# ==================== Constants ====================
const
  # Window
  WindowWidth = 1280
  WindowHeight = 720
  WindowTitle = "NimCraft - GUI & API Edition"
  
  # World
  WorldSize = 32
  ChunkSize = 16
  RenderDistance = 4
  BlockTypes = 5
  MaxStackSize = 64
  
  # Physics
  Gravity = -0.02
  PlayerSpeed = 0.1
  JumpStrength = 0.3
  MouseSensitivity = 0.002
  
  # API
  ApiPort = 8080
  ApiToken = "nimcraft-secret-2024"  # In production, use env vars
  MaxPlayers = 10
  
  # UI
  HotbarSize = 9
  InventorySize = 27
  CraftingGridSize = 4

# ==================== Types ====================
type
  # Math types
  Vec3* = object
    x*, y*, z*: float32
  
  Vec2* = object
    u*, v*: float32
  
  Color* = object
    r*, g*, b*, a*: float32
  
  # Game types
  BlockType* = enum
    btAir = 0
    btGrass = 1
    btDirt = 2
    btStone = 3
    btWood = 4
    btGlass = 5
    btCrafting = 6
    btFurnace = 7
    btChest = 8
  
  Block* = object
    type*: BlockType
    active*: bool
    metadata*: int  # For block states (furnace lit, chest contents, etc.)
  
  Chunk* = object
    blocks*: array[ChunkSize, array[ChunkSize, array[ChunkSize, Block]]]
    position*: (int, int)
    mesh*: seq[float32]
    vao*, vbo*, ebo*: uint32
    indexCount*: int
    dirty*: bool
    lastAccessed*: float
  
  World* = object
    chunks*: Table[(int, int), Chunk]
    seed*: int64
    time*: float32
    weather*: Weather
  
  Weather* = enum
    wtClear, wtRain, wtThunder
  
  # Player types
  PlayerInventory* = object
    slots*: array[HotbarSize + InventorySize, ItemStack]
    hotbarSlot*: int
    craftingGrid*: array[CraftingGridSize, ItemStack]
    craftingResult*: ItemStack
  
  ItemStack* = object
    itemType*: BlockType
    count*: int
    durability*: int
    metadata*: JsonNode  # For custom item data
  
  Player* = object
    id*: string
    name*: string
    pos*: Vec3
    rot*: Vec3
    velocity*: Vec3
    onGround*: bool
    inventory*: PlayerInventory
    health*: int
    maxHealth*: int
    food*: int
    experience*: float
    level*: int
    selectedBlock*: BlockType
    gameMode*: GameMode
  
  GameMode* = enum
    gmSurvival, gmCreative, gmAdventure, gmSpectator
  
  Camera* = object
    pos*, front*, up*, right*: Vec3
    yaw*, pitch*: float32
    fov*: float32
  
  # GUI Types
  GuiElement* = ref object of RootObj
    id*: string
    bounds*: (int, int, int, int)  # x, y, width, height
    visible*: bool
    enabled*: bool
    parent*: GuiElement
    children*: seq[GuiElement]
    zIndex*: int
    backgroundColor*: Color
    borderColor*: Color
    borderWidth*: int
    onClick*: proc()
    onHover*: proc()
    onDrag*: proc(dx, dy: int)
  
  GuiScreen* = enum
    gsMainMenu
    gsGame
    gsInventory
    gsCrafting
    gsChest
    gsPause
    gsSettings
    gsMultiplayer
    gsApiDashboard
  
  Label* = ref object of GuiElement
    text*: string
    font*: string
    fontSize*: int
    color*: Color
  
  Button* = ref object of GuiElement
    text*: string
    icon*: string
    state*: ButtonState
  
  ButtonState* = enum
    bsNormal, bsHovered, bsPressed, bsDisabled
  
  TextBox* = ref object of GuiElement
    text*: string
    placeholder*: string
    cursorPos*: int
    focused*: bool
  
  Slider* = ref object of GuiElement
    value*: float
    min*: float
    max*: float
    step*: float
  
  ItemSlot* = ref object of GuiElement
    stack*: ItemStack
    index*: int
  
  InventoryGui* = ref object of GuiElement
    playerInventory*: PlayerInventory
  
  ChatBox* = ref object of GuiElement
    messages*: seq[ChatMessage]
    input*: string
    visible*: bool
  
  ChatMessage* = object
    text*: string
    sender*: string
    timestamp*: float
    color*: Color
  
  # API Types
  ApiServer* = ref object
    socket*: AsyncSocket
    running*: bool
    clients*: seq[ApiClient]
    commands*: Table[string, ApiCommand]
  
  ApiClient* = ref object
    socket*: AsyncSocket
    id*: string
    authenticated*: bool
    lastPing*: float
  
  ApiCommand* = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.gcsafe, async.}
  
  ApiRequest* = object
    command*: string
    params*: JsonNode
    token*: string
  
  ApiResponse* = object
    success*: bool
    data*: JsonNode
    error*: string
  
  # Network types
  NetworkPlayer* = object
    id*: string
    name*: string
    pos*: Vec3
    rot*: Vec3
  
  Server* = ref object
    socket*: AsyncSocket
    clients*: Table[string, NetworkPlayer]
    world*: World
  
  # Game
  Game* = ref object
    window*: GLFWwindow
    world*: World
    player*: Player
    camera*: Camera
    shaders*: Table[string, uint32]
    textures*: Table[string, uint32]
    fonts*: Table[string, pointer]
    sounds*: Table[string, pointer]
    
    # Time
    lastTime*: float64
    deltaTime*: float32
    fps*: int
    frameCount*: int
    frameTimer*: float
    
    # GUI
    currentScreen*: GuiScreen
    guiElements*: seq[GuiElement]
    hoveredElement*: GuiElement
    draggedElement*: GuiElement
    modalStack*: seq[GuiElement]
    chat*: ChatBox
    
    # API
    api*: ApiServer
    apiEnabled*: bool
    
    # Network
    server*: Server
    isServer*: bool
    isClient*: bool
    
    # Input
    mouseCaptured*: bool
    keysPressed*: set[char]
    mouseX*, mouseY*: int
    scrollDelta*: int
    
    # Settings
    settings*: GameSettings
    debug*: bool
  
  GameSettings* = object
    renderDistance*: int
    fov*: float32
    mouseSensitivity*: float32
    volume*: float32
    viewBobbing*: bool
    vsync*: bool
    fullscreen*: bool
    apiPort*: int
    serverAddress*: string

# ==================== Math Utilities ====================
proc vec3*(x, y, z: float32): Vec3 = Vec3(x: x, y: y, z: z)
proc vec3*(x, y, z: int): Vec3 = vec3(x.float32, y.float32, z.float32)
proc vec2*(u, v: float32): Vec2 = Vec2(u: u, v: v)
proc color*(r, g, b, a: float32): Color = Color(r: r, g: g, b: b, a: a)

proc `+`*(a, b: Vec3): Vec3 = vec3(a.x + b.x, a.y + b.y, a.z + b.z)
proc `-`*(a, b: Vec3): Vec3 = vec3(a.x - b.x, a.y - b.y, a.z - b.z)
proc `*`*(a: Vec3, s: float32): Vec3 = vec3(a.x * s, a.y * s, a.z * s)
proc `/`*(a: Vec3, s: float32): Vec3 = vec3(a.x / s, a.y / s, a.z / s)
proc `*`*(a, b: Vec3): float32 = a.x*b.x + a.y*b.y + a.z*b.z
proc len*(a: Vec3): float32 = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
proc normalize*(a: Vec3): Vec3 = 
  let l = a.len
  if l > 0: a / l else: a
proc cross*(a, b: Vec3): Vec3 = vec3(
  a.y*b.z - a.z*b.y,
  a.z*b.x - a.x*b.z,
  a.x*b.y - a.y*b.x
)

# ==================== Shaders ====================
const
  vertexShaderSrc = """
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aTexCoord;
layout (location = 2) in vec3 aNormal;
layout (location = 3) in vec4 aColor;

out vec2 TexCoord;
out vec3 Normal;
out vec3 FragPos;
out vec4 VertexColor;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main() {
    FragPos = vec3(model * vec4(aPos, 1.0));
    gl_Position = projection * view * vec4(FragPos, 1.0);
    TexCoord = aTexCoord;
    Normal = mat3(transpose(inverse(model))) * aNormal;
    VertexColor = aColor;
}
"""

  fragmentShaderSrc = """
#version 330 core
out vec4 FragColor;

in vec2 TexCoord;
in vec3 Normal;
in vec3 FragPos;
in vec4 VertexColor;

uniform sampler2D texture1;
uniform vec3 lightPos;
uniform vec3 viewPos;
uniform vec3 lightColor;
uniform float time;
uniform int guiMode;

void main() {
    if (guiMode == 1) {
        // GUI rendering - no lighting
        FragColor = VertexColor * texture(texture1, TexCoord);
        return;
    }
    
    // 3D world rendering with lighting
    // Ambient
    float ambientStrength = 0.3;
    vec3 ambient = ambientStrength * lightColor;
    
    // Diffuse
    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(lightPos - FragPos);
    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * lightColor;
    
    // Specular
    float specularStrength = 0.5;
    vec3 viewDir = normalize(viewPos - FragPos);
    vec3 reflectDir = reflect(-lightDir, norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    vec3 specular = specularStrength * spec * lightColor;
    
    vec3 result = (ambient + diffuse + specular) * lightColor;
    FragColor = vec4(result, 1.0) * texture(texture1, TexCoord) * VertexColor;
    
    // Time-based effects
    float flicker = sin(time * 10.0 + FragPos.x) * 0.1 + 0.9;
    FragColor.rgb *= flicker;
}
"""

  guiVertexShaderSrc = """
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aTexCoord;
layout (location = 3) in vec4 aColor;

out vec2 TexCoord;
out vec4 VertexColor;

uniform mat4 projection;

void main() {
    gl_Position = projection * vec4(aPos, 1.0);
    TexCoord = aTexCoord;
    VertexColor = aColor;
}
"""

# ==================== GUI System ====================
proc newLabel*(text: string, x, y, width, height: int): Label =
  result = Label(
    id: "label_" & $getTime(),
    text: text,
    bounds: (x, y, width, height),
    visible: true,
    enabled: true,
    color: color(1, 1, 1, 1),
    fontSize: 12,
    zIndex: 0
  )

proc newButton*(text: string, x, y, width, height: int, onClick: proc()): Button =
  result = Button(
    id: "btn_" & $getTime(),
    text: text,
    bounds: (x, y, width, height),
    visible: true,
    enabled: true,
    state: bsNormal,
    onClick: onClick,
    backgroundColor: color(0.2, 0.2, 0.2, 1),
    borderColor: color(0.5, 0.5, 0.5, 1),
    borderWidth: 1,
    zIndex: 0
  )

proc newTextBox*(x, y, width, height: int, placeholder: string): TextBox =
  result = TextBox(
    id: "textbox_" & $getTime(),
    bounds: (x, y, width, height),
    visible: true,
    enabled: true,
    text: "",
    placeholder: placeholder,
    cursorPos: 0,
    focused: false,
    backgroundColor: color(0.1, 0.1, 0.1, 1),
    borderColor: color(0.3, 0.3, 0.3, 1),
    borderWidth: 1,
    zIndex: 0
  )

proc newSlider*(x, y, width, height: int, minVal, maxVal, initial: float): Slider =
  result = Slider(
    id: "slider_" & $getTime(),
    bounds: (x, y, width, height),
    visible: true,
    enabled: true,
    value: initial,
    min: minVal,
    max: maxVal,
    step: 0.01,
    backgroundColor: color(0.2, 0.2, 0.2, 1),
    borderColor: color(0.5, 0.5, 0.5, 1),
    borderWidth: 1,
    zIndex: 0
  )

proc newChatBox*(x, y, width, height: int): ChatBox =
  result = ChatBox(
    id: "chat_" & $getTime(),
    messages: @[],
    input: "",
    bounds: (x, y, width, height),
    visible: true,
    enabled: true,
    backgroundColor: color(0, 0, 0, 0.5),
    borderColor: color(1, 1, 1, 0.2),
    borderWidth: 1,
    zIndex: 100
  )

proc addMessage*(chat: ChatBox, sender, text: string) =
  let msg = ChatMessage(
    text: text,
    sender: sender,
    timestamp: epochTime(),
    color: color(1, 1, 1, 1)
  )
  chat.messages.add(msg)
  if chat.messages.len > 100:
    chat.messages.delete(0)

proc handleGuiInput*(game: Game, x, y: int, clicked: bool) =
  # Find hovered element
  for elem in game.guiElements:
    let (ex, ey, ew, eh) = elem.bounds
    if x >= ex and x <= ex + ew and y >= ey and y <= ey + eh:
      game.hoveredElement = elem
      if clicked and elem.enabled:
        if elem.onClick != nil:
          elem.onClick()
        
        if elem of TextBox:
          TextBox(elem).focused = true
        else:
          # Unfocus other text boxes
          for e in game.guiElements:
            if e of TextBox:
              TextBox(e).focused = false
    
    if elem of TextBox and TextBox(elem).focused:
      TextBox(elem).cursorPos = TextBox(elem).text.len

proc renderGui*(game: Game) =
  # Setup orthographic projection for GUI
  var projection = ortho(0.0, WindowWidth.float32, WindowHeight.float32, 0.0, -1.0, 1.0)
  
  glUseProgram(game.shaders["gui"])
  glUniformMatrix4fv(glGetUniformLocation(game.shaders["gui"], "projection"), 1, GL_FALSE, addr projection[0][0])
  glUniform1i(glGetUniformLocation(game.shaders["gui"], "guiMode"), 1)
  
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  
  # Sort by z-index
  let sorted = game.guiElements.sortedByIt(it.zIndex)
  
  for elem in sorted:
    if not elem.visible: continue
    
    let (x, y, w, h) = elem.bounds
    
    # Render background
    glBegin(GL_QUADS)
    glColor4f(elem.backgroundColor.r, elem.backgroundColor.g, 
              elem.backgroundColor.b, elem.backgroundColor.a)
    glVertex2f(x.float32, y.float32)
    glVertex2f((x + w).float32, y.float32)
    glVertex2f((x + w).float32, (y + h).float32)
    glVertex2f(x.float32, (y + h).float32)
    glEnd()
    
    # Render border
    if elem.borderWidth > 0:
      glLineWidth(elem.borderWidth.float32)
      glBegin(GL_LINE_LOOP)
      glColor4f(elem.borderColor.r, elem.borderColor.g, 
                elem.borderColor.b, elem.borderColor.a)
      glVertex2f(x.float32, y.float32)
      glVertex2f((x + w).float32, y.float32)
      glVertex2f((x + w).float32, (y + h).float32)
      glVertex2f(x.float32, (y + h).float32)
      glEnd()
    
    # Render element-specific content
    if elem of Label:
      let label = Label(elem)
      # Simple text rendering (would use actual font rendering in production)
      glRasterPos2f((x + 5).float32, (y + 20).float32)
      glColor4f(label.color.r, label.color.g, label.color.b, label.color.a)
      for c in label.text:
        glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
    
    elif elem of Button:
      let btn = Button(elem)
      # Button text
      glRasterPos2f((x + w div 2 - btn.text.len * 4).float32, (y + h div 2 + 5).float32)
      glColor4f(1, 1, 1, 1)
      for c in btn.text:
        glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
      
      # Hover effect
      if btn.state == bsHovered:
        glEnable(GL_BLEND)
        glBegin(GL_QUADS)
        glColor4f(1, 1, 1, 0.2)
        glVertex2f(x.float32, y.float32)
        glVertex2f((x + w).float32, y.float32)
        glVertex2f((x + w).float32, (y + h).float32)
        glVertex2f(x.float32, (y + h).float32)
        glEnd()
    
    elif elem of TextBox:
      let tb = TextBox(elem)
      let displayText = if tb.text.len > 0: tb.text else: tb.placeholder
      glRasterPos2f((x + 5).float32, (y + h div 2 + 5).float32)
      glColor4f(if tb.text.len > 0: 1 else: 0.5, 1, 1, 1)
      for c in displayText:
        glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
      
      # Cursor
      if tb.focused and (getTime() * 2).int mod 2 == 0:
        glBegin(GL_LINES)
        glColor4f(1, 1, 1, 1)
        let cursorX = x + 5 + tb.cursorPos * 8
        glVertex2f(cursorX.float32, (y + 5).float32)
        glVertex2f(cursorX.float32, (y + h - 5).float32)
        glEnd()
    
    elif elem of Slider:
      let s = Slider(elem)
      let fillWidth = ((s.value - s.min) / (s.max - s.min) * w.float32).int
      
      # Fill
      glBegin(GL_QUADS)
      glColor4f(0.3, 0.6, 1, 1)
      glVertex2f(x.float32, y.float32)
      glVertex2f((x + fillWidth).float32, y.float32)
      glVertex2f((x + fillWidth).float32, (y + h).float32)
      glVertex2f(x.float32, (y + h).float32)
      glEnd()
    
    elif elem of ChatBox:
      let chat = ChatBox(elem)
      var yOffset = h - 20
      
      # Messages (newest at bottom)
      for i in countdown(chat.messages.len - 1, max(0, chat.messages.len - 10)):
        let msg = chat.messages[i]
        glRasterPos2f((x + 5).float32, (y + yOffset).float32)
        glColor4f(msg.color.r, msg.color.g, msg.color.b, msg.color.a)
        let displayText = &"[{msg.sender}] {msg.text}"
        for c in displayText:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
        yOffset -= 15
      
      # Input
      glRasterPos2f((x + 5).float32, (y + 15).float32)
      glColor4f(1, 1, 1, 1)
      let inputText = "> " & chat.input
      for c in inputText:
        glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glEnable(GL_DEPTH_TEST)
  glDisable(GL_BLEND)

# ==================== API Server ====================
proc initApiServer*(): ApiServer =
  result = ApiServer(
    socket: newAsyncSocket(),
    running: false,
    clients: @[],
    commands: initTable[string, ApiCommand]()
  )

proc handleApiRequest(client: ApiClient, data: string) {.async.} =
  try:
    let req = parseJson(data).to(ApiRequest)
    
    # Authenticate
    if req.token != ApiToken and req.command != "auth":
      await client.socket.send($(%ApiResponse(success: false, error: "Unauthorized")))
      return
    
    # Execute command
    if client.authenticated or req.command == "auth":
      if client.commands.hasKey(req.command):
        let result = await client.commands[req.command](client, req.params)
        await client.socket.send($(%ApiResponse(success: true, data: result)))
      else:
        await client.socket.send($(%ApiResponse(success: false, error: "Unknown command")))
    else:
      await client.socket.send($(%ApiResponse(success: false, error: "Not authenticated")))
  except:
    await client.socket.send($(%ApiResponse(success: false, error: getCurrentExceptionMsg())))

proc registerApiCommands*(api: ApiServer, game: Game) =
  # Auth command
  api.commands["auth"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    if params{"token"}.getStr() == ApiToken:
      client.authenticated = true
      result = %*{"status": "authenticated", "clientId": client.id}
    else:
      raise newException(ValueError, "Invalid token")
  
  # Get world info
  api.commands["getWorld"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    result = %*{
      "seed": game.world.seed,
      "time": game.world.time,
      "weather": $game.world.weather,
      "playerCount": game.server.clients.len
    }
  
  # Get player info
  api.commands["getPlayer"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let playerId = params{"playerId"}.getStr(game.player.id)
    if playerId == game.player.id:
      result = %*{
        "id": game.player.id,
        "name": game.player.name,
        "position": {
          "x": game.player.pos.x,
          "y": game.player.pos.y,
          "z": game.player.pos.z
        },
        "health": game.player.health,
        "food": game.player.food,
        "level": game.player.level,
        "gameMode": $game.player.gameMode
      }
    else:
      # Get other player from network
      if game.server.clients.hasKey(playerId):
        let p = game.server.clients[playerId]
        result = %*{
          "id": p.id,
          "name": p.name,
          "position": {
            "x": p.pos.x,
            "y": p.pos.y,
            "z": p.pos.z
          }
        }
      else:
        raise newException(ValueError, "Player not found")
  
  # Get blocks in area
  api.commands["getBlocks"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let x = params{"x"}.getInt(0)
    let y = params{"y"}.getInt(0)
    let z = params{"z"}.getInt(0)
    let radius = params{"radius"}.getInt(5)
    
    var blocks: seq[JsonNode] = @[]
    for dx in -radius..radius:
      for dy in -radius..radius:
        for dz in -radius..radius:
          let bx = x + dx
          let by = y + dy
          let bz = z + dz
          let block = getBlock(game.world, bx, by, bz)
          if block.typ != btAir:
            blocks.add(%*{
              "x": bx, "y": by, "z": bz,
              "type": $block.typ,
              "active": block.active,
              "metadata": block.metadata
            })
    
    result = %*{"blocks": blocks}
  
  # Place block
  api.commands["placeBlock"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let x = params{"x"}.getInt()
    let y = params{"y"}.getInt()
    let z = params{"z"}.getInt()
    let blockType = parseEnum[BlockType](params{"type"}.getStr("btStone"))
    
    if setBlock(game.world, x, y, z, Block(typ: blockType, active: true)):
      # Broadcast to all clients
      for c in game.server.clients.values:
        discard  # Would send update
      
      result = %*{"success": true, "block": {"x": x, "y": y, "z": z, "type": $blockType}}
    else:
      raise newException(ValueError, "Cannot place block")
  
  # Mine block
  api.commands["mineBlock"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let x = params{"x"}.getInt()
    let y = params{"y"}.getInt()
    let z = params{"z"}.getInt()
    
    let block = getBlock(game.world, x, y, z)
    if block.typ != btAir and setBlock(game.world, x, y, z, Block(typ: btAir, active: false)):
      result = %*{"success": true, "mined": {"x": x, "y": y, "z": z, "type": $block.typ}}
    else:
      raise newException(ValueError, "Cannot mine block")
  
  # Move player
  api.commands["movePlayer"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let x = params{"x"}.getFloat(game.player.pos.x)
    let y = params{"y"}.getFloat(game.player.pos.y)
    let z = params{"z"}.getFloat(game.player.pos.z)
    
    game.player.pos = vec3(x, y, z)
    result = %*{"success": true, "newPosition": {"x": x, "y": y, "z": z}}
  
  # Execute command
  api.commands["command"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let cmd = params{"cmd"}.getStr()
    let args = params{"args"}.getStr("")
    
    case cmd
    of "time set":
      game.world.time = args.parseFloat()
      result = %*{"success": true, "message": &"Time set to {args}"}
    of "weather":
      game.world.weather = parseEnum[Weather](args)
      result = %*{"success": true, "message": &"Weather set to {args}"}
    of "gamemode":
      game.player.gameMode = parseEnum[GameMode](args)
      result = %*{"success": true, "message": &"Gamemode set to {args}"}
    else:
      raise newException(ValueError, "Unknown command")
  
  # Get inventory
  api.commands["getInventory"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    var slots: seq[JsonNode] = @[]
    for i, stack in game.player.inventory.slots:
      if stack.count > 0:
        slots.add(%*{
          "slot": i,
          "type": $stack.itemType,
          "count": stack.count,
          "durability": stack.durability,
          "metadata": stack.metadata
        })
    
    result = %*{
      "hotbarSlot": game.player.inventory.hotbarSlot,
      "slots": slots
    }
  
  # Chat message
  api.commands["chat"] = proc(client: ApiClient, params: JsonNode): Future[JsonNode] {.async.} =
    let message = params{"message"}.getStr()
    let sender = params{"sender"}.getStr("API")
    
    game.chat.addMessage(sender, message)
    result = %*{"success": true, "message": "Message sent"}

proc startApiServer*(api: ApiServer, port: int) {.async.} =
  api.running = true
  await api.socket.bindAddr(port.Port)
  await api.socket.listen()
  
  echo &"API Server listening on port {port}"
  
  while api.running:
    try:
      let clientSocket = await api.socket.accept()
      let client = ApiClient(
        socket: clientSocket,
        id: $genUUID(),
        authenticated: false,
        lastPing: epochTime()
      )
      api.clients.add(client)
      
      # Handle client in new coroutine
      asyncCheck handleApiClient(api, client)
    except:
      echo "API accept error: ", getCurrentExceptionMsg()

proc handleApiClient*(api: ApiServer, client: ApiClient) {.async.} =
  try:
    while api.running:
      let data = await client.socket.recvLine()
      if data.len == 0:
        break
      
      await handleApiRequest(client, data)
      client.lastPing = epochTime()
  finally:
    client.socket.close()
    api.clients.delete(api.clients.find(client))

# ==================== GUI Screens ====================
proc createMainMenu(game: Game): seq[GuiElement] =
  result = @[]
  
  # Title
  result.add(newLabel("NimCraft", WindowWidth div 2 - 100, 100, 200, 50))
  
  # Buttons
  result.add(newButton("Singleplayer", WindowWidth div 2 - 100, 200, 200, 40, proc() =
    game.currentScreen = gsGame
    game.mouseCaptured = true
  ))
  
  result.add(newButton("Multiplayer", WindowWidth div 2 - 100, 250, 200, 40, proc() =
    game.currentScreen = gsMultiplayer
  ))
  
  result.add(newButton("Settings", WindowWidth div 2 - 100, 300, 200, 40, proc() =
    game.currentScreen = gsSettings
  ))
  
  result.add(newButton("API Dashboard", WindowWidth div 2 - 100, 350, 200, 40, proc() =
    game.currentScreen = gsApiDashboard
  ))
  
  result.add(newButton("Quit", WindowWidth div 2 - 100, 400, 200, 40, proc() =
    glfwSetWindowShouldClose(game.window, 1)
  ))

proc createSettingsMenu(game: Game): seq[GuiElement] =
  result = @[]
  
  result.add(newLabel("Settings", WindowWidth div 2 - 50, 50, 100, 30))
  
  # Render distance
  result.add(newLabel("Render Distance:", 200, 120, 150, 20))
  let rdSlider = newSlider(360, 120, 200, 20, 2, 16, game.settings.renderDistance.float)
  rdSlider.onDrag = proc(dx, dy: int) =
    game.settings.renderDistance = rdSlider.value.int
  result.add(rdSlider)
  
  # FOV
  result.add(newLabel("FOV:", 200, 150, 150, 20))
  let fovSlider = newSlider(360, 150, 200, 20, 60, 110, game.settings.fov)
  fovSlider.onDrag = proc(dx, dy: int) =
    game.settings.fov = fovSlider.value
    game.camera.fov = fovSlider.value
  result.add(fovSlider)
  
  # Mouse sensitivity
  result.add(newLabel("Mouse Sensitivity:", 200, 180, 150, 20))
  let sensSlider = newSlider(360, 180, 200, 20, 0.001, 0.01, game.settings.mouseSensitivity)
  sensSlider.onDrag = proc(dx, dy: int) =
    game.settings.mouseSensitivity = sensSlider.value
  result.add(sensSlider)
  
  # Volume
  result.add(newLabel("Volume:", 200, 210, 150, 20))
  let volSlider = newSlider(360, 210, 200, 20, 0, 1, game.settings.volume)
  volSlider.onDrag = proc(dx, dy: int) =
    game.settings.volume = volSlider.value
  result.add(volSlider)
  
  # Checkboxes
  result.add(newLabel("View Bobbing:", 200, 240, 150, 20))
  # Would add checkbox
  
  result.add(newLabel("VSync:", 200, 270, 150, 20))
  # Would add checkbox
  
  # API Port
  result.add(newLabel("API Port:", 200, 300, 150, 20))
  let apiPortBox = newTextBox(360, 300, 100, 25, "8080")
  apiPortBox.text = $game.settings.apiPort
  result.add(apiPortBox)
  
  # Back button
  result.add(newButton("Back", WindowWidth div 2 - 50, 500, 100, 30, proc() =
    game.currentScreen = gsMainMenu
  ))

proc createMultiplayerMenu(game: Game): seq[GuiElement] =
  result = @[]
  
  result.add(newLabel("Multiplayer", WindowWidth div 2 - 60, 50, 120, 30))
  
  # Server address
  result.add(newLabel("Server Address:", 200, 120, 120, 20))
  let serverBox = newTextBox(330, 120, 200, 25, "localhost:25565")
  serverBox.text = game.settings.serverAddress
  result.add(serverBox)
  
  # Connect button
  result.add(newButton("Connect", WindowWidth div 2 - 60, 200, 120, 30, proc() =
    # Connect to server
    game.currentScreen = gsGame
    game.isClient = true
  ))
  
  # Start server button
  result.add(newButton("Start Server", WindowWidth div 2 - 60, 250, 120, 30, proc() =
    # Start local server
    game.isServer = true
    game.currentScreen = gsGame
  ))
  
  # Back button
  result.add(newButton("Back", WindowWidth div 2 - 60, 500, 120, 30, proc() =
    game.currentScreen = gsMainMenu
  ))

proc createApiDashboard(game: Game): seq[GuiElement] =
  result = @[]
  
  result.add(newLabel("API Dashboard", WindowWidth div 2 - 70, 30, 140, 30))
  
  # API Status
  let statusText = if game.apiEnabled: "Running" else: "Stopped"
  result.add(newLabel(&"Status: {statusText}", 200, 80, 200, 20))
  result.add(newLabel(&"Port: {game.settings.apiPort}", 200, 105, 200, 20))
  result.add(newLabel(&"Connected Clients: {game.api.clients.len}", 200, 130, 200, 20))
  
  # API Token
  result.add(newLabel(&"API Token: {ApiToken}", 200, 160, 300, 20))
  
  # Start/Stop button
  result.add(newButton(if game.apiEnabled: "Stop API" else: "Start API", 
                       200, 200, 120, 30, proc() =
    if game.apiEnabled:
      game.api.running = false
      game.apiEnabled = false
    else:
      game.apiEnabled = true
      asyncCheck game.api.startApiServer(game.settings.apiPort)
  ))
  
  # Test API button
  result.add(newButton("Test API", 200, 240, 120, 30, proc() =
    asyncCheck testApiConnection()
  ))
  
  # Commands list
  var y = 300
  result.add(newLabel("Available Commands:", 200, y, 200, 20))
  y += 25
  for cmd in ["auth", "getWorld", "getPlayer", "getBlocks", "placeBlock", 
              "mineBlock", "movePlayer", "command", "getInventory", "chat"]:
    result.add(newLabel(&"  • {cmd}", 220, y, 200, 15))
    y += 18
  
  # Back button
  result.add(newButton("Back", WindowWidth div 2 - 50, 600, 100, 30, proc() =
    game.currentScreen = gsMainMenu
  ))

proc createInventoryGui(game: Game): seq[GuiElement] =
  result = @[]
  
  # Background
  let bg = newLabel("", 100, 100, 400, 300)
  bg.backgroundColor = color(0, 0, 0, 0.8)
  result.add(bg)
  
  # Title
  result.add(newLabel("Inventory", 250, 120, 100, 20))
  
  # Player inventory slots
  for i in 0..<InventorySize:
    let row = i div 9
    let col = i mod 9
    let slot = ItemSlot(
      id: "slot_" & $i,
      bounds: (150 + col * 40, 200 + row * 40, 36, 36),
      visible: true,
      enabled: true,
      stack: game.player.inventory.slots[i + HotbarSize],
      index: i + HotbarSize,
      backgroundColor: color(0.3, 0.3, 0.3, 1),
      borderColor: color(0.5, 0.5, 0.5, 1),
      borderWidth: 1,
      zIndex: 1
    )
    result.add(slot)
  
  # Hotbar
  for i in 0..<HotbarSize:
    let slot = ItemSlot(
      id: "hotbar_" & $i,
      bounds: (150 + i * 40, 350, 36, 36),
      visible: true,
      enabled: true,
      stack: game.player.inventory.slots[i],
      index: i,
      backgroundColor: if i == game.player.inventory.hotbarSlot: color(0.6, 0.6, 0.6, 1) 
                       else: color(0.3, 0.3, 0.3, 1),
      borderColor: color(1, 1, 1, 1),
      borderWidth: 2,
      zIndex: 1
    )
    result.add(slot)
  
  # Close button
  result.add(newButton("Close", 400, 380, 80, 25, proc() =
    game.currentScreen = gsGame
  ))

# ==================== API Test Client ====================
proc testApiConnection*() {.async.} =
  try:
    let client = newAsyncSocket()
    await client.connect("localhost", ApiPort.Port)
    
    # Authenticate
    let authReq = %*{
      "command": "auth",
      "token": ApiToken,
      "params": {"token": ApiToken}
    }
    await client.send($authReq & "\n")
    let authResp = await client.recvLine()
    echo "Auth response: ", authResp
    
    # Get world info
    let worldReq = %*{
      "command": "getWorld",
      "token": ApiToken,
      "params": {}
    }
    await client.send($worldReq & "\n")
    let worldResp = await client.recvLine()
    echo "World response: ", worldResp
    
    # Place a block
    let placeReq = %*{
      "command": "placeBlock",
      "token": ApiToken,
      "params": {
        "x": 10,
        "y": 64,
        "z": 10,
        "type": "btStone"
      }
    }
    await client.send($placeReq & "\n")
    let placeResp = await client.recvLine()
    echo "Place block response: ", placeResp
    
    client.close()
  except:
    echo "API test failed: ", getCurrentExceptionMsg()

# ==================== World Generation ====================
proc generateHeight*(x, z: int): int =
  let freq1 = 0.05
  let freq2 = 0.1
  let freq3 = 0.2
  
  var h = int(sin(x.float * freq1) * cos(z.float * freq1) * 8 +
              sin(x.float * freq2) * 4 +
              cos(z.float * freq2) * 4 +
              sin(x.float * freq3) * 2 +
              cos(z.float * freq3) * 2 +
              32)
  return max(1, h)

proc generateChunk*(world: var World, cx, cz: int) =
  var chunk: Chunk
  chunk.position = (cx, cz)
  chunk.lastAccessed = epochTime()
  
  for x in 0..<ChunkSize:
    for z in 0..<ChunkSize:
      let worldX = cx * ChunkSize + x
      let worldZ = cz * ChunkSize + z
      let height = generateHeight(worldX, worldZ)
      
      for y in 0..<ChunkSize:
        let worldY = y
        var block: Block
        
        if worldY < height - 4:
          block.typ = btStone
          block.active = true
        elif worldY < height - 1:
          block.typ = btDirt
          block.active = true
        elif worldY < height:
          block.typ = btGrass
          block.active = true
        elif worldY == height and rand(1.0) < 0.02:
          block.typ = btWood
          block.active = true
        elif worldY == height + 1 and rand(1.0) < 0.01:
          block.typ = btChest
          block.active = true
          block.metadata = rand(1000)  # Chest ID
        else:
          block.typ = btAir
          block.active = false
        
        chunk.blocks[x][y][z] = block
  
  chunk.dirty = true
  world.chunks[(cx, cz)] = chunk

proc getBlock*(world: World, x, y, z: int): Block =
  let cx = floorDiv(x, ChunkSize)
  let cz = floorDiv(z, ChunkSize)
  let key = (cx, cz)
  
  if world.chunks.hasKey(key):
    let lx = x mod ChunkSize
    let lz = z mod ChunkSize
    if y >= 0 and y < ChunkSize:
      return world.chunks[key].blocks[lx][y][lz]
  
  return Block(typ: btAir, active: false)

proc setBlock*(world: var World, x, y, z: int, block: Block): bool =
  let cx = floorDiv(x, ChunkSize)
  let cz = floorDiv(z, ChunkSize)
  let key = (cx, cz)
  
  if world.chunks.hasKey(key):
    let lx = x mod ChunkSize
    let lz = z mod ChunkSize
    if y >= 0 and y < ChunkSize:
      world.chunks[key].blocks[lx][y][lz] = block
      world.chunks[key].dirty = true
      return true
  
  return false

# ==================== Mesh Generation ====================
proc isBlockVisible*(world: World, x, y, z: int): bool =
  let block = getBlock(world, x, y, z)
  if not block.active: return false
  
  # Check neighboring blocks
  let neighbors = [
    (x+1, y, z), (x-1, y, z),
    (x, y+1, z), (x, y-1, z),
    (x, y, z+1), (x, y, z-1)
  ]
  
  for (nx, ny, nz) in neighbors:
    let neighbor = getBlock(world, nx, ny, nz)
    if not neighbor.active:
      return true
  
  return false

proc generateMesh*(world: var World, cx, cz: int) =
  if not world.chunks.hasKey((cx, cz)): return
  var chunk = addr world.chunks[(cx, cz)]
  if not chunk.dirty: return
  
  chunk.mesh = @[]
  let baseX = cx * ChunkSize
  let baseZ = cz * ChunkSize
  
  for x in 0..<ChunkSize:
    for y in 0..<ChunkSize:
      for z in 0..<ChunkSize:
        if not chunk.blocks[x][y][z].active: continue
        
        let worldX = baseX + x
        let worldY = y
        let worldZ = baseZ + z
        let blockType = chunk.blocks[x][y][z].typ.float32 / BlockTypes.float32
        
        # Each face: position (3) + texcoord (2) + normal (3) + color (4) = 12 floats
        # Front face
        if isBlockVisible(world, worldX, worldY, worldZ-1):
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, blockType, 0,0,1, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, worldZ.float32, 1, blockType, 0,0,1, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, worldZ.float32, 1, blockType+0.1, 0,0,1, 1,1,1,1])
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, blockType, 0,0,1, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, worldZ.float32, 1, blockType+0.1, 0,0,1, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, worldZ.float32, 0, blockType+0.1, 0,0,1, 1,1,1,1])
        
        # Back face
        if isBlockVisible(world, worldX, worldY, worldZ+1):
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+1).float32, 1, blockType, 0,0,-1, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, (worldZ+1).float32, 1, blockType+0.1, 0,0,-1, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, (worldZ+1).float32, 0, blockType+0.1, 0,0,-1, 1,1,1,1])
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+1).float32, 1, blockType, 0,0,-1, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, (worldZ+1).float32, 0, blockType+0.1, 0,0,-1, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, (worldZ+1).float32, 0, blockType, 0,0,-1, 1,1,1,1])
        
        # Left face
        if isBlockVisible(world, worldX-1, worldY, worldZ):
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, blockType, -1,0,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+1).float32, 1, blockType, -1,0,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, (worldZ+1).float32, 1, blockType+0.1, -1,0,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, blockType, -1,0,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, (worldZ+1).float32, 1, blockType+0.1, -1,0,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, worldZ.float32, 0, blockType+0.1, -1,0,0, 1,1,1,1])
        
        # Right face
        if isBlockVisible(world, worldX+1, worldY, worldZ):
          chunk.mesh.add([(worldX+1).float32, worldY.float32, worldZ.float32, 1, blockType, 1,0,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, worldZ.float32, 1, blockType+0.1, 1,0,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, (worldZ+1).float32, 0, blockType+0.1, 1,0,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, worldZ.float32, 1, blockType, 1,0,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, (worldZ+1).float32, 0, blockType+0.1, 1,0,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, (worldZ+1).float32, 0, blockType, 1,0,0, 1,1,1,1])
        
        # Bottom face
        if isBlockVisible(world, worldX, worldY-1, worldZ):
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, blockType, 0,-1,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, worldZ.float32, 1, blockType, 0,-1,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, (worldZ+1).float32, 1, blockType+0.1, 0,-1,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, blockType, 0,-1,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, worldY.float32, (worldZ+1).float32, 1, blockType+0.1, 0,-1,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+1).float32, 0, blockType+0.1, 0,-1,0, 1,1,1,1])
        
        # Top face
        if isBlockVisible(world, worldX, worldY+1, worldZ):
          chunk.mesh.add([worldX.float32, (worldY+1).float32, worldZ.float32, 0, blockType+0.1, 0,1,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, (worldZ+1).float32, 1, blockType+0.1, 0,1,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, (worldZ+1).float32, 1, blockType+0.2, 0,1,0, 1,1,1,1])
          chunk.mesh.add([worldX.float32, (worldY+1).float32, worldZ.float32, 0, blockType+0.1, 0,1,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, (worldZ+1).float32, 1, blockType+0.2, 0,1,0, 1,1,1,1])
          chunk.mesh.add([(worldX+1).float32, (worldY+1).float32, worldZ.float32, 1, blockType+0.2, 0,1,0, 1,1,1,1])
  
  # Update VBO
  if chunk.vao == 0:
    glGenVertexArrays(1, addr chunk.vao)
    glGenBuffers(1, addr chunk.vbo)
  
  glBindVertexArray(chunk.vao)
  glBindBuffer(GL_ARRAY_BUFFER, chunk.vbo)
  
  if chunk.mesh.len > 0:
    glBufferData(GL_ARRAY_BUFFER, chunk.mesh.len * sizeof(float32), 
                 addr chunk.mesh[0], GL_STATIC_DRAW)
    
    # Position attribute
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 12 * sizeof(float32), cast[pointer](0))
    glEnableVertexAttribArray(0)
    
    # Texture attribute
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 12 * sizeof(float32), 
                          cast[pointer](3 * sizeof(float32)))
    glEnableVertexAttribArray(1)
    
    # Normal attribute
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 12 * sizeof(float32), 
                          cast[pointer](5 * sizeof(float32)))
    glEnableVertexAttribArray(2)
    
    # Color attribute
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, 12 * sizeof(float32), 
                          cast[pointer](8 * sizeof(float32)))
    glEnableVertexAttribArray(3)
  
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  
  chunk.dirty = false
  chunk.lastAccessed = epochTime()

# ==================== Player ====================
proc initPlayer*(id, name: string): Player =
  result = Player(
    id: id,
    name: name,
    pos: vec3(0, 40, 0),
    velocity: vec3(0, 0, 0),
    onGround: false,
    health: 20,
    maxHealth: 20,
    food: 20,
    experience: 0,
    level: 0,
    selectedBlock: btGrass,
    gameMode: gmSurvival
  )
  
  # Initialize inventory
  for i in 0..<result.inventory.slots.len:
    if i < 5:  # Give starter blocks
      result.inventory.slots[i] = ItemStack(itemType: btGrass, count: 64)
    else:
      result.inventory.slots[i] = ItemStack(itemType: btAir, count: 0)
  
  result.inventory.hotbarSlot = 0

# ==================== Game Initialization ====================
proc initGame*(playerName: string = "Player"): Game =
  new(result)
  
  # Initialize GLFW
  if glfwInit() == 0:
    quit("Failed to initialize GLFW")
  
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
  
  result.window = glfwCreateWindow(WindowWidth, WindowHeight, WindowTitle, nil, nil)
  if result.window == nil:
    quit("Failed to create window")
  
  glfwMakeContextCurrent(result.window)
  glfwSetInputMode(result.window, GLFW_CURSOR, GLFW_CURSOR_DISABLED)
  glfwSwapInterval(1)
  
  # Load OpenGL
  if not glfwLoadOpenGL():
    quit("Failed to load OpenGL")
  
  # Set callbacks
  glfwSetWindowUserPointer(result.window, result)
  glfwSetKeyCallback(result.window, keyCallback)
  glfwSetCursorPosCallback(result.window, mouseCallback)
  glfwSetMouseButtonCallback(result.window, mouseButtonCallback)
  glfwSetScrollCallback(result.window, scrollCallback)
  
  # Initialize OpenGL
  glEnable(GL_DEPTH_TEST)
  glEnable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glClearColor(0.5, 0.7, 1.0, 1.0)
  
  # Compile shaders
  result.shaders = initTable[string, uint32]()
  result.shaders["world"] = createShaderProgram(vertexShaderSrc, fragmentShaderSrc)
  result.shaders["gui"] = createShaderProgram(guiVertexShaderSrc, fragmentShaderSrc)
  
  # Initialize world
  result.world = World(
    seed: getTime().int,
    time: 0,
    weather: wtClear,
    chunks: initTable[(int, int), Chunk]()
  )
  
  # Generate initial chunks
  for x in -RenderDistance..RenderDistance:
    for z in -RenderDistance..RenderDistance:
      generateChunk(result.world, x, z)
  
  # Initialize player
  result.player = initPlayer($genUUID(), playerName)
  
  # Initialize camera
  result.camera = Camera(
    pos: result.player.pos,
    front: vec3(0, 0, -1),
    up: vec3(0, 1, 0),
    right: vec3(1, 0, 0),
    yaw: -90.0,
    pitch: 0.0,
    fov: 70.0
  )
  
  # Initialize settings
  result.settings = GameSettings(
    renderDistance: 4,
    fov: 70.0,
    mouseSensitivity: 0.002,
    volume: 0.5,
    viewBobbing: true,
    vsync: true,
    fullscreen: false,
    apiPort: ApiPort,
    serverAddress: "localhost:25565"
  )
  
  # Initialize GUI
  result.currentScreen = gsMainMenu
  result.guiElements = createMainMenu(result[])
  result.chat = newChatBox(20, 20, 400, 200)
  result.guiElements.add(result.chat)
  
  # Initialize API
  result.api = initApiServer()
  result.api.registerApiCommands(result[])
  result.apiEnabled = false
  
  # Initialize server
  result.server = Server(
    socket: newAsyncSocket(),
    clients: initTable[string, NetworkPlayer](),
    world: result.world
  )
  
  result.debug = false

# ==================== Input Callbacks ====================
proc keyCallback*(window: GLFWwindow, key, scancode, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  
  if key == GLFW_KEY_ESCAPE and action == GLFW_PRESS:
    if game.currentScreen == gsGame:
      game.currentScreen = gsPause
      game.mouseCaptured = false
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL)
    else:
      game.currentScreen = gsMainMenu
  
  elif key == GLFW_KEY_E and action == GLFW_PRESS:
    if game.currentScreen == gsGame:
      game.currentScreen = gsInventory
      game.mouseCaptured = false
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL)
    elif game.currentScreen == gsInventory:
      game.currentScreen = gsGame
      game.mouseCaptured = true
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED)
  
  elif key == GLFW_KEY_T and action == GLFW_PRESS:
    game.chat.visible = not game.chat.visible
    if game.chat.visible:
      game.mouseCaptured = false
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL)
    else:
      game.mouseCaptured = true
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED)
  
  elif key == GLFW_KEY_F3 and action == GLFW_PRESS:
    game.debug = not game.debug
  
  elif key == GLFW_KEY_F1 and action == GLFW_PRESS:
    game.currentScreen = gsApiDashboard
  
  # Number keys for hotbar
  if key >= GLFW_KEY_1 and key <= GLFW_KEY_9 and action == GLFW_PRESS:
    game.player.inventory.hotbarSlot = key.int - GLFW_KEY_1.int
    game.player.selectedBlock = game.player.inventory.slots[game.player.inventory.hotbarSlot].itemType

proc mouseCallback*(window: GLFWwindow, xpos, ypos: float64) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  
  if not game.mouseCaptured:
    game.mouseX = xpos.int
    game.mouseY = ypos.int
    handleGuiInput(game[], xpos.int, ypos.int, false)
    return
  
  var dx = float32(xpos - WindowWidth div 2) * game.settings.mouseSensitivity
  var dy = float32(WindowHeight div 2 - ypos) * game.settings.mouseSensitivity
  
  game.camera.yaw += dx
  game.camera.pitch += dy
  
  if game.camera.pitch > 89.0: game.camera.pitch = 89.0
  if game.camera.pitch < -89.0: game.camera.pitch = -89.0
  
  var front: Vec3
  front.x = cos(degToRad(game.camera.yaw)) * cos(degToRad(game.camera.pitch))
  front.y = sin(degToRad(game.camera.pitch))
  front.z = sin(degToRad(game.camera.yaw)) * cos(degToRad(game.camera.pitch))
  game.camera.front = normalize(front)
  game.camera.right = normalize(cross(game.camera.front, vec3(0, 1, 0)))
  game.camera.up = normalize(cross(game.camera.right, game.camera.front))
  
  # Reset cursor to center
  glfwSetCursorPos(window, WindowWidth.float64 / 2, WindowHeight.float64 / 2)

proc mouseButtonCallback*(window: GLFWwindow, button, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  
  if not game.mouseCaptured:
    handleGuiInput(game[], game.mouseX, game.mouseY, action == GLFW_PRESS)
    return
  
  if button == GLFW_MOUSE_BUTTON_LEFT and action == GLFW_PRESS:
    # Raycast for block mining
    let step = 0.1
    var pos = game.camera.pos
    let dir = game.camera.front * step
    
    for i in 0..<50:
      pos = pos + dir
      let blockX = int(floor(pos.x))
      let blockY = int(floor(pos.y))
      let blockZ = int(floor(pos.z))
      
      let block = getBlock(game.world, blockX, blockY, blockZ)
      if block.active and block.typ != btAir:
        # Remove block
        setBlock(game.world, blockX, blockY, blockZ, Block(typ: btAir, active: false))
        
        # Add to inventory
        if game.player.gameMode != gmCreative:
          for i in 0..<game.player.inventory.slots.len:
            if game.player.inventory.slots[i].itemType == block.typ and 
               game.player.inventory.slots[i].count < MaxStackSize:
              game.player.inventory.slots[i].count += 1
              break
            elif game.player.inventory.slots[i].itemType == btAir:
              game.player.inventory.slots[i] = ItemStack(itemType: block.typ, count: 1)
              break
        
        break
  
  elif button == GLFW_MOUSE_BUTTON_RIGHT and action == GLFW_PRESS:
    # Raycast for block placement
    let step = 0.1
    var pos = game.camera.pos
    let dir = game.camera.front * step
    var lastPos = pos
    
    for i in 0..<50:
      pos = pos + dir
      let blockX = int(floor(pos.x))
      let blockY = int(floor(pos.y))
      let blockZ = int(floor(pos.z))
      
      let block = getBlock(game.world, blockX, blockY, blockZ)
      if block.active and block.typ != btAir:
        # Place block adjacent to face
        let placeX = int(floor(lastPos.x))
        let placeY = int(floor(lastPos.y))
        let placeZ = int(floor(lastPos.z))
        
        let targetBlock = getBlock(game.world, placeX, placeY, placeZ)
        if not targetBlock.active:
          # Check inventory
          let selectedSlot = game.player.inventory.hotbarSlot
          if game.player.inventory.slots[selectedSlot].count > 0 or 
             game.player.gameMode == gmCreative:
            
            setBlock(game.world, placeX, placeY, placeZ, 
                    Block(typ: game.player.selectedBlock, active: true))
            
            if game.player.gameMode != gmCreative:
              game.player.inventory.slots[selectedSlot].count -= 1
              if game.player.inventory.slots[selectedSlot].count <= 0:
                game.player.inventory.slots[selectedSlot] = ItemStack(itemType: btAir, count: 0)
        
        break
      lastPos = pos

proc scrollCallback*(window: GLFWwindow, xoffset, yoffset: float64) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  game.scrollDelta = yoffset.int
  
  # Change hotbar slot
  if game.mouseCaptured:
    var newSlot = game.player.inventory.hotbarSlot + yoffset.int
    if newSlot < 0: newSlot = HotbarSize - 1
    if newSlot >= HotbarSize: newSlot = 0
    game.player.inventory.hotbarSlot = newSlot
    game.player.selectedBlock = game.player.inventory.slots[newSlot].itemType

# ==================== Shader Helpers ====================
proc createShader*(shaderType: uint32, source: string): uint32 =
  result = glCreateShader(shaderType)
  var cstr = source.cstring
  var len = source.len.GLint
  glShaderSource(result, 1, addr cstr, addr len)
  glCompileShader(result)
  
  var success: GLint
  glGetShaderiv(result, GL_COMPILE_STATUS, addr success)
  if success == GL_FALSE:
    var infoLog: array[512, char]
    glGetShaderInfoLog(result, 512, nil, addr infoLog[0])
    echo "Shader compilation failed: ", infoLog

proc createShaderProgram*(vertexSrc, fragmentSrc: string): uint32 =
  let vertexShader = createShader(GL_VERTEX_SHADER, vertexSrc)
  let fragmentShader = createShader(GL_FRAGMENT_SHADER, fragmentSrc)
  
  result = glCreateProgram()
  glAttachShader(result, vertexShader)
  glAttachShader(result, fragmentShader)
  glLinkProgram(result)
  
  var success: GLint
  glGetProgramiv(result, GL_LINK_STATUS, addr success)
  if success == GL_FALSE:
    var infoLog: array[512, char]
    glGetProgramInfoLog(result, 512, nil, addr infoLog[0])
    echo "Program linking failed: ", infoLog
  
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)

# ==================== Game Loop ====================
proc updatePlayer*(game: Game) =
  let speed = PlayerSpeed * game.deltaTime * 60  # Normalize to 60 FPS
  
  # Handle keyboard input
  if glfwGetKey(game.window, GLFW_KEY_W) == GLFW_PRESS:
    game.player.pos = game.player.pos + game.camera.front * speed
  if glfwGetKey(game.window, GLFW_KEY_S) == GLFW_PRESS:
    game.player.pos = game.player.pos - game.camera.front * speed
  if glfwGetKey(game.window, GLFW_KEY_A) == GLFW_PRESS:
    game.player.pos = game.player.pos - game.camera.right * speed
  if glfwGetKey(game.window, GLFW_KEY_D) == GLFW_PRESS:
    game.player.pos = game.player.pos + game.camera.right * speed
  
  # Jump
  if glfwGetKey(game.window, GLFW_KEY_SPACE) == GLFW_PRESS and game.player.onGround:
    game.player.velocity.y = JumpStrength
  
  # Apply gravity
  game.player.velocity.y += Gravity * game.deltaTime * 60
  game.player.pos.y += game.player.velocity.y
  
  # Simple collision detection
  game.player.onGround = false
  let blockX = int(floor(game.player.pos.x))
  let blockY = int(floor(game.player.pos.y))
  let blockZ = int(floor(game.player.pos.z))
  
  let block = getBlock(game.world, blockX, blockY, blockZ)
  if block.active:
    if game.player.velocity.y < 0:
      game.player.pos.y = ceil(game.player.pos.y - 1.0)
      game.player.velocity.y = 0
      game.player.onGround = true
  
  # Update camera
  game.camera.pos = game.player.pos
  
  # View bobbing
  if game.settings.viewBobbing and game.player.onGround and 
     (glfwGetKey(game.window, GLFW_KEY_W) == GLFW_PRESS or
      glfwGetKey(game.window, GLFW_KEY_S) == GLFW_PRESS or
      glfwGetKey(game.window, GLFW_KEY_A) == GLFW_PRESS or
      glfwGetKey(game.window, GLFW_KEY_D) == GLFW_PRESS):
    let bobAmount = sin(game.world.time * 10) * 0.03
    game.camera.pos.y += bobAmount

proc renderWorld*(game: Game) =
  glUseProgram(game.shaders["world"])
  
  # Set uniforms
  var view = identityMatrix4()
  view = lookAt(game.camera.pos, game.camera.pos + game.camera.front, vec3(0, 1, 0))
  
  var projection = perspective(game.camera.fov, WindowWidth / WindowHeight, 0.1, 1000.0)
  
  glUniformMatrix4fv(glGetUniformLocation(game.shaders["world"], "view"), 1, GL_FALSE, addr view[0][0])
  glUniformMatrix4fv(glGetUniformLocation(game.shaders["world"], "projection"), 1, GL_FALSE, addr projection[0][0])
  glUniform3f(glGetUniformLocation(game.shaders["world"], "lightPos"), 
              100 * sin(game.world.time), 100, 100 * cos(game.world.time))
  glUniform3f(glGetUniformLocation(game.shaders["world"], "viewPos"), 
              game.camera.pos.x, game.camera.pos.y, game.camera.pos.z)
  glUniform3f(glGetUniformLocation(game.shaders["world"], "lightColor"), 1, 1, 1)
  glUniform1f(glGetUniformLocation(game.shaders["world"], "time"), game.world.time)
  glUniform1i(glGetUniformLocation(game.shaders["world"], "guiMode"), 0)
  
  # Render chunks
  let playerChunkX = floorDiv(int(game.player.pos.x), ChunkSize)
  let playerChunkZ = floorDiv(int(game.player.pos.z), ChunkSize)
  
  for x in -game.settings.renderDistance..game.settings.renderDistance:
    for z in -game.settings.renderDistance..game.settings.renderDistance:
      let chunkX = playerChunkX + x
      let chunkZ = playerChunkZ + z
      let key = (chunkX, chunkZ)
      
      if not game.world.chunks.hasKey(key):
        generateChunk(game.world, chunkX, chunkZ)
      
      if game.world.chunks[key].dirty:
        generateMesh(game.world, chunkX, chunkZ)
      
      if game.world.chunks[key].mesh.len > 0:
        var model = translate(identityMatrix4(), vec3(
          float32(chunkX * ChunkSize),
          0,
          float32(chunkZ * ChunkSize)
        ))
        
        glUniformMatrix4fv(glGetUniformLocation(game.shaders["world"], "model"), 
                          1, GL_FALSE, addr model[0][0])
        
        glBindVertexArray(game.world.chunks[key].vao)
        glDrawArrays(GL_TRIANGLES, 0, (game.world.chunks[key].mesh.len div 12).GLsizei)

proc renderDebug*(game: Game) =
  if not game.debug: return
  
  # Use immediate mode for debug overlay
  glUseProgram(0)
  glDisable(GL_DEPTH_TEST)
  
  # Setup orthographic projection for text
  glMatrixMode(GL_PROJECTION)
  glPushMatrix()
  glLoadIdentity()
  glOrtho(0, WindowWidth, WindowHeight, 0, -1, 1)
  
  glMatrixMode(GL_MODELVIEW)
  glPushMatrix()
  glLoadIdentity()
  
  # Draw debug text
  glColor3f(1, 1, 1)
  glRasterPos2f(10, 20)
  let fpsText = &"FPS: {game.fps}"
  for c in fpsText:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glRasterPos2f(10, 40)
  let posText = &"Pos: {game.player.pos.x:.1f}, {game.player.pos.y:.1f}, {game.player.pos.z:.1f}"
  for c in posText:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glRasterPos2f(10, 60)
  let chunkText = &"Chunk: {playerChunkX}, {playerChunkZ}"
  for c in chunkText:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glRasterPos2f(10, 80)
  let blockText = &"Block: {getBlock(game.world, int(game.player.pos.x), int(game.player.pos.y), int(game.player.pos.z)).typ}"
  for c in blockText:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glRasterPos2f(10, 100)
  let apiText = &"API: {'Running' if game.apiEnabled else 'Stopped'} ({game.api.clients.len} clients)"
  for c in apiText:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glMatrixMode(GL_PROJECTION)
  glPopMatrix()
  glMatrixMode(GL_MODELVIEW)
  glPopMatrix()
  
  glEnable(GL_DEPTH_TEST)

proc renderHotbar*(game: Game) =
  # Use GUI shader for hotbar
  glUseProgram(game.shaders["gui"])
  
  var projection = ortho(0.0, WindowWidth.float32, WindowHeight.float32, 0.0, -1.0, 1.0)
  glUniformMatrix4fv(glGetUniformLocation(game.shaders["gui"], "projection"), 
                     1, GL_FALSE, addr projection[0][0])
  glUniform1i(glGetUniformLocation(game.shaders["gui"], "guiMode"), 1)
  
  # Draw hotbar background
  let hotbarX = WindowWidth div 2 - HotbarSize * 20
  let hotbarY = WindowHeight - 50
  
  glBegin(GL_QUADS)
  glColor4f(0, 0, 0, 0.5)
  glVertex2f(hotbarX.float32, hotbarY.float32)
  glVertex2f((hotbarX + HotbarSize * 40).float32, hotbarY.float32)
  glVertex2f((hotbarX + HotbarSize * 40).float32, (hotbarY + 40).float32)
  glVertex2f(hotbarX.float32, (hotbarY + 40).float32)
  glEnd()
  
  # Draw slots
  for i in 0..<HotbarSize:
    let slotX = hotbarX + i * 40
    let slotY = hotbarY
    
    # Slot background
    glBegin(GL_QUADS)
    if i == game.player.inventory.hotbarSlot:
      glColor4f(1, 1, 1, 0.3)
    else:
      glColor4f(0.3, 0.3, 0.3, 0.5)
    glVertex2f(slotX.float32, slotY.float32)
    glVertex2f((slotX + 36).float32, slotY.float32)
    glVertex2f((slotX + 36).float32, (slotY + 36).float32)
    glVertex2f(slotX.float32, (slotY + 36).float32)
    glEnd()
    
    # Slot border
    glBegin(GL_LINE_LOOP)
    glColor4f(1, 1, 1, 0.8)
    glVertex2f(slotX.float32, slotY.float32)
    glVertex2f((slotX + 36).float32, slotY.float32)
    glVertex2f((slotX + 36).float32, (slotY + 36).float32)
    glVertex2f(slotX.float32, (slotY + 36).float32)
    glEnd()
    
    # Item count
    let stack = game.player.inventory.slots[i]
    if stack.count > 0:
      glRasterPos2f((slotX + 25).float32, (slotY + 25).float32)
      glColor4f(1, 1, 1, 1)
      let countText = $stack.count
      for c in countText:
        glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)

proc render*(game: Game) =
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  
  # Update world time
  game.world.time += game.deltaTime * 0.1
  
  # Render 3D world
  renderWorld(game)
  
  # Render GUI (if not in game mode or if game mode with GUI elements)
  if game.currentScreen != gsGame or game.chat.visible:
    renderGui(game)
  
  # Always render hotbar in game mode
  if game.currentScreen == gsGame:
    renderHotbar(game)
  
  # Render debug overlay
  renderDebug(game)
  
  glfwSwapBuffers(game.window)
  glfwPollEvents()
  
  # Update FPS counter
  game.frameCount += 1
  let currentTime = glfwGetTime()
  if currentTime - game.frameTimer >= 1.0:
    game.fps = game.frameCount
    game.frameCount = 0
    game.frameTimer = currentTime

proc run*(game: Game) =
  game.lastTime = glfwGetTime()
  game.frameTimer = game.lastTime
  
  while glfwWindowShouldClose(game.window) == 0:
    let currentTime = glfwGetTime()
    game.deltaTime = float32(currentTime - game.lastTime)
    game.lastTime = currentTime
    
    if game.currentScreen == gsGame and game.mouseCaptured:
      updatePlayer(game)
    
    render(game)
    
    # Frame rate limiter
    if game.deltaTime < 1.0/60.0:
      sleep(int((1.0/60.0 - game.deltaTime) * 1000))
  
  # Cleanup
  glfwDestroyWindow(game.window)
  glfwTerminate()

# ==================== Main ====================
proc main() =
  echo "Starting NimCraft with GUI and API..."
  
  let game = initGame("Player")
  
  # Start API server if enabled
  if game.apiEnabled:
    asyncCheck game.api.startApiServer(game.settings.apiPort)
  
  # Run the game
  game.run()

when isMainModule:

  main()
