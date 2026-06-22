import std/[math, random, os, times, strformat]
import opengl, glfw3

# Constants
const
  WindowWidth = 1024
  WindowHeight = 768
  WorldSize = 32
  ChunkSize = 16
  BlockTypes = 4
  RenderDistance = 4
  Gravity = -0.02
  PlayerSpeed = 0.1
  JumpStrength = 0.3
  MouseSensitivity = 0.002

# Types
type
  Vec3 = object
    x, y, z: float32
  
  BlockType = enum
    btAir, btGrass, btDirt, btStone, btWood
  
  Block = object
    typ: BlockType
    active: bool
  
  Chunk = object
    blocks: array[ChunkSize, array[ChunkSize, array[ChunkSize, Block]]]
    position: (int, int)
    mesh: seq[float32]
    vao, vbo: uint32
    dirty: bool
  
  World = object
    chunks: array[-RenderDistance..RenderDistance, 
                  array[-RenderDistance..RenderDistance, Chunk]]
  
  Player = object
    pos: Vec3
    rot: Vec3
    velocity: Vec3
    onGround: bool
  
  Camera = object
    pos, front, up, right: Vec3
    yaw, pitch: float32
  
  Game = object
    window: GLFWwindow
    world: World
    player: Player
    camera: Camera
    shader: uint32
    lastTime: float64
    deltaTime: float32
    blockInHand: BlockType
    wireframe: bool
    mouseCaptured: bool

# Utility functions
proc vec3(x, y, z: float32): Vec3 = Vec3(x: x, y: y, z: z)
proc `+`(a, b: Vec3): Vec3 = vec3(a.x + b.x, a.y + b.y, a.z + b.z)
proc `-`(a, b: Vec3): Vec3 = vec3(a.x - b.x, a.y - b.y, a.z - b.z)
proc `*`(a: Vec3, s: float32): Vec3 = vec3(a.x * s, a.y * s, a.z * s)
proc `/`(a: Vec3, s: float32): Vec3 = vec3(a.x / s, a.y / s, a.z / s)
proc len(a: Vec3): float32 = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
proc normalize(a: Vec3): Vec3 = a / a.len
proc dot(a, b: Vec3): float32 = a.x*b.x + a.y*b.y + a.z*b.z
proc cross(a, b: Vec3): Vec3 = vec3(
  a.y*b.z - a.z*b.y,
  a.z*b.x - a.x*b.z,
  a.x*b.y - a.y*b.x
)

# Shaders
const
  vertexShaderSrc = """
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aTexCoord;
layout (location = 2) in vec3 aNormal;

out vec2 TexCoord;
out vec3 Normal;
out vec3 FragPos;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main() {
    FragPos = vec3(model * vec4(aPos, 1.0));
    gl_Position = projection * view * vec4(FragPos, 1.0);
    TexCoord = aTexCoord;
    Normal = mat3(transpose(inverse(model))) * aNormal;
}
"""

  fragmentShaderSrc = """
#version 330 core
out vec4 FragColor;

in vec2 TexCoord;
in vec3 Normal;
in vec3 FragPos;

uniform sampler2D texture1;
uniform vec3 lightPos;
uniform vec3 viewPos;
uniform vec3 lightColor;
uniform vec3 objectColor;

void main() {
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
    
    vec3 result = (ambient + diffuse + specular) * objectColor;
    FragColor = vec4(result, 1.0) * texture(texture1, TexCoord);
}
"""

# Shader compilation
proc compileShader(shaderType: uint32, source: string): uint32 =
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

proc createShaderProgram(): uint32 =
  let vertexShader = compileShader(GL_VERTEX_SHADER, vertexShaderSrc)
  let fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentShaderSrc)
  
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

# World generation
proc generateHeight(x, z: int): int =
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

proc generateChunk(world: var World, cx, cz: int) =
  var chunk: Chunk
  chunk.position = (cx, cz)
  
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
        elif worldY == height and rand(1.0) < 0.05:
          block.typ = btWood
          block.active = true
        else:
          block.typ = btAir
          block.active = false
        
        chunk.blocks[x][y][z] = block
  
  chunk.dirty = true
  world.chunks[cx][cz] = chunk

# Mesh generation
proc isBlockVisible(world: World, x, y, z: int): bool =
  let cx = floorDiv(x, ChunkSize)
  let cz = floorDiv(z, ChunkSize)
  let lx = x mod ChunkSize
  let lz = z mod ChunkSize
  
  if cx < -RenderDistance or cx > RenderDistance or 
     cz < -RenderDistance or cz > RenderDistance:
    return false
  
  let chunk = world.chunks[cx][cz]
  if y < 0 or y >= ChunkSize: return false
  
  if not chunk.blocks[lx][y][lz].active: return false
  
  # Check neighboring blocks
  let neighbors = [
    (x+1, y, z), (x-1, y, z),
    (x, y+1, z), (x, y-1, z),
    (x, y, z+1), (x, y, z-1)
  ]
  
  for (nx, ny, nz) in neighbors:
    let ncx = floorDiv(nx, ChunkSize)
    let ncz = floorDiv(nz, ChunkSize)
    if ncx < -RenderDistance or ncx > RenderDistance or 
       ncz < -RenderDistance or ncz > RenderDistance:
      continue
    
    let nlx = nx mod ChunkSize
    let nlz = nz mod ChunkSize
    if ny >= 0 and ny < ChunkSize:
      if not world.chunks[ncx][ncz].blocks[nlx][ny][nlz].active:
        return true
  
  return false

proc generateMesh(world: var World, cx, cz: int) =
  var chunk = addr world.chunks[cx][cz]
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
        
        # Block vertices and texture coordinates
        let blockSize = 1.0
        let texSize = 1.0 / BlockTypes.float32
        let texY = chunk.blocks[x][y][z].typ.float32 * texSize
        
        # Front face
        if isBlockVisible(world, worldX, worldY, worldZ-1):
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, texY, 0,0,1])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, worldZ.float32, texSize, texY, 0,0,1])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, worldZ.float32, texSize, texY+texSize, 0,0,1])
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, texY, 0,0,1])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, worldZ.float32, texSize, texY+texSize, 0,0,1])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, worldZ.float32, 0, texY+texSize, 0,0,1])
        
        # Back face
        if isBlockVisible(world, worldX, worldY, worldZ+1):
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+blockSize).float32, texSize, texY, 0,0,-1])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, texSize, texY+texSize, 0,0,-1])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, 0, texY+texSize, 0,0,-1])
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+blockSize).float32, texSize, texY, 0,0,-1])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, 0, texY+texSize, 0,0,-1])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, (worldZ+blockSize).float32, 0, texY, 0,0,-1])
        
        # Left face
        if isBlockVisible(world, worldX-1, worldY, worldZ):
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, texY, -1,0,0])
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+blockSize).float32, texSize, texY, -1,0,0])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, texSize, texY+texSize, -1,0,0])
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, texY, -1,0,0])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, texSize, texY+texSize, -1,0,0])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, worldZ.float32, 0, texY+texSize, -1,0,0])
        
        # Right face
        if isBlockVisible(world, worldX+1, worldY, worldZ):
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, worldZ.float32, texSize, texY, 1,0,0])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, worldZ.float32, texSize, texY+texSize, 1,0,0])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, 0, texY+texSize, 1,0,0])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, worldZ.float32, texSize, texY, 1,0,0])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, 0, texY+texSize, 1,0,0])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, (worldZ+blockSize).float32, 0, texY, 1,0,0])
        
        # Bottom face
        if isBlockVisible(world, worldX, worldY-1, worldZ):
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, texY, 0,-1,0])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, worldZ.float32, texSize, texY, 0,-1,0])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, (worldZ+blockSize).float32, texSize, texY+texSize, 0,-1,0])
          chunk.mesh.add([worldX.float32, worldY.float32, worldZ.float32, 0, texY, 0,-1,0])
          chunk.mesh.add([(worldX+blockSize).float32, worldY.float32, (worldZ+blockSize).float32, texSize, texY+texSize, 0,-1,0])
          chunk.mesh.add([worldX.float32, worldY.float32, (worldZ+blockSize).float32, 0, texY+texSize, 0,-1,0])
        
        # Top face
        if isBlockVisible(world, worldX, worldY+1, worldZ):
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, worldZ.float32, 0, texY, 0,1,0])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, texSize, texY, 0,1,0])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, texSize, texY+texSize, 0,1,0])
          chunk.mesh.add([worldX.float32, (worldY+blockSize).float32, worldZ.float32, 0, texY, 0,1,0])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, (worldZ+blockSize).float32, texSize, texY+texSize, 0,1,0])
          chunk.mesh.add([(worldX+blockSize).float32, (worldY+blockSize).float32, worldZ.float32, texSize, texY+texSize, 0,1,0])
  
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
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float32), cast[pointer](0))
    glEnableVertexAttribArray(0)
    
    # Texture attribute
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(float32), 
                          cast[pointer](3 * sizeof(float32)))
    glEnableVertexAttribArray(1)
    
    # Normal attribute
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float32), 
                          cast[pointer](5 * sizeof(float32)))
    glEnableVertexAttribArray(2)
  
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  
  chunk.dirty = false

# Input handling
proc keyCallback(window: GLFWwindow, key, scancode, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  if key == GLFW_KEY_ESCAPE and action == GLFW_PRESS:
    game.mouseCaptured = not game.mouseCaptured
    glfwSetInputMode(window, GLFW_CURSOR, 
                     if game.mouseCaptured: GLFW_CURSOR_DISABLED else: GLFW_CURSOR_NORMAL)
  elif key == GLFW_KEY_F3 and action == GLFW_PRESS:
    game.wireframe = not game.wireframe
    glPolygonMode(GL_FRONT_AND_BACK, if game.wireframe: GL_LINE else: GL_FILL)
  elif key in [GLFW_KEY_1, GLFW_KEY_2, GLFW_KEY_3, GLFW_KEY_4] and action == GLFW_PRESS:
    game.blockInHand = BlockType(key.int - GLFW_KEY_1.int + 1)

proc mouseCallback(window: GLFWwindow, xpos, ypos: float64) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  if not game.mouseCaptured: return
  
  var dx = float32(xpos - 400) * MouseSensitivity
  var dy = float32(300 - ypos) * MouseSensitivity
  
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

proc mouseButtonCallback(window: GLFWwindow, button, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  if not game.mouseCaptured: return
  
  if button == GLFW_MOUSE_BUTTON_LEFT and action == GLFW_PRESS:
    # Raycast for block removal
    let step = 0.1
    var pos = game.camera.pos
    let dir = game.camera.front * step
    
    for i in 0..<50:
      pos = pos + dir
      let blockX = int(floor(pos.x))
      let blockY = int(floor(pos.y))
      let blockZ = int(floor(pos.z))
      
      let cx = floorDiv(blockX, ChunkSize)
      let cz = floorDiv(blockZ, ChunkSize)
      let lx = blockX mod ChunkSize
      let lz = blockZ mod ChunkSize
      
      if cx in -RenderDistance..RenderDistance and 
         cz in -RenderDistance..RenderDistance and
         blockY in 0..<ChunkSize:
        if game.world.chunks[cx][cz].blocks[lx][blockY][lz].active:
          game.world.chunks[cx][cz].blocks[lx][blockY][lz].active = false
          game.world.chunks[cx][cz].dirty = true
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
      
      let cx = floorDiv(blockX, ChunkSize)
      let cz = floorDiv(blockZ, ChunkSize)
      let lx = blockX mod ChunkSize
      let lz = blockZ mod ChunkSize
      
      if cx in -RenderDistance..RenderDistance and 
         cz in -RenderDistance..RenderDistance and
         blockY in 0..<ChunkSize:
        if game.world.chunks[cx][cz].blocks[lx][blockY][lz].active:
          let placeX = int(floor(lastPos.x))
          let placeY = int(floor(lastPos.y))
          let placeZ = int(floor(lastPos.z))
          
          let placeCx = floorDiv(placeX, ChunkSize)
          let placeCz = floorDiv(placeZ, ChunkSize)
          let placeLx = placeX mod ChunkSize
          let placeLz = placeZ mod ChunkSize
          
          if placeY >= 0 and placeY < ChunkSize:
            if not game.world.chunks[placeCx][placeCz].blocks[placeLx][placeY][placeLz].active:
              game.world.chunks[placeCx][placeCz].blocks[placeLx][placeY][placeLz].active = true
              game.world.chunks[placeCx][placeCz].blocks[placeLx][placeY][placeLz].typ = game.blockInHand
              game.world.chunks[placeCx][placeCz].dirty = true
          break
      lastPos = pos

# Game initialization
proc initGame(): Game =
  randomize()
  
  # Initialize GLFW
  if glfwInit() == 0:
    quit("Failed to initialize GLFW")
  
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
  
  result.window = glfwCreateWindow(WindowWidth, WindowHeight, "NimCraft", nil, nil)
  if result.window == nil:
    quit("Failed to create window")
  
  glfwMakeContextCurrent(result.window)
  glfwSetInputMode(result.window, GLFW_CURSOR, GLFW_CURSOR_DISABLED)
  glfwSwapInterval(1)
  
  # Load OpenGL
  if not glfwLoadOpenGL():
    quit("Failed to load OpenGL")
  
  # Set callbacks
  glfwSetWindowUserPointer(result.window, addr result)
  glfwSetKeyCallback(result.window, keyCallback)
  glfwSetCursorPosCallback(result.window, mouseCallback)
  glfwSetMouseButtonCallback(result.window, mouseButtonCallback)
  
  # Initialize OpenGL
  glEnable(GL_DEPTH_TEST)
  glEnable(GL_CULL_FACE)
  glClearColor(0.5, 0.7, 1.0, 1.0)
  
  # Create shader
  result.shader = createShaderProgram()
  
  # Initialize player
  result.player.pos = vec3(0, 40, 0)
  result.mouseCaptured = true
  
  # Initialize camera
  result.camera.pos = result.player.pos
  result.camera.yaw = -90.0
  result.camera.pitch = 0.0
  result.camera.front = vec3(0, 0, -1)
  
  # Generate world
  for x in -RenderDistance..RenderDistance:
    for z in -RenderDistance..RenderDistance:
      generateChunk(result.world, x, z)
  
  result.blockInHand = btGrass

# Update functions
proc updatePlayer(game: var Game) =
  # Handle keyboard input
  let speed = PlayerSpeed * game.deltaTime
  
  if glfwGetKey(game.window, GLFW_KEY_W) == GLFW_PRESS:
    game.player.pos = game.player.pos + game.camera.front * speed
  if glfwGetKey(game.window, GLFW_KEY_S) == GLFW_PRESS:
    game.player.pos = game.player.pos - game.camera.front * speed
  if glfwGetKey(game.window, GLFW_KEY_A) == GLFW_PRESS:
    game.player.pos = game.player.pos - game.camera.right * speed
  if glfwGetKey(game.window, GLFW_KEY_D) == GLFW_PRESS:
    game.player.pos = game.player.pos + game.camera.right * speed
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
  
  let cx = floorDiv(blockX, ChunkSize)
  let cz = floorDiv(blockZ, ChunkSize)
  let lx = blockX mod ChunkSize
  let lz = blockZ mod ChunkSize
  
  if cx in -RenderDistance..RenderDistance and 
     cz in -RenderDistance..RenderDistance and
     blockY in 0..<ChunkSize:
    if game.world.chunks[cx][cz].blocks[lx][blockY][lz].active:
      if game.player.velocity.y < 0:
        game.player.pos.y = ceil(game.player.pos.y - 1.0)
        game.player.velocity.y = 0
        game.player.onGround = true
  
  # Update camera position
  game.camera.pos = game.player.pos

proc render(game: var Game) =
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  
  glUseProgram(game.shader)
  
  # Set uniforms
  var view = identityMatrix4()
  view = lookAt(game.camera.pos, game.camera.pos + game.camera.front, vec3(0, 1, 0))
  
  var projection = perspective(45.0, WindowWidth / WindowHeight, 0.1, 1000.0)
  
  glUniformMatrix4fv(glGetUniformLocation(game.shader, "view"), 1, GL_FALSE, addr view[0][0])
  glUniformMatrix4fv(glGetUniformLocation(game.shader, "projection"), 1, GL_FALSE, addr projection[0][0])
  glUniform3f(glGetUniformLocation(game.shader, "lightPos"), 100, 100, 100)
  glUniform3f(glGetUniformLocation(game.shader, "viewPos"), game.camera.pos.x, game.camera.pos.y, game.camera.pos.z)
  glUniform3f(glGetUniformLocation(game.shader, "lightColor"), 1, 1, 1)
  glUniform3f(glGetUniformLocation(game.shader, "objectColor"), 0.8, 0.8, 0.8)
  
  # Render chunks
  for x in -RenderDistance..RenderDistance:
    for z in -RenderDistance..RenderDistance:
      if game.world.chunks[x][z].dirty:
        generateMesh(game, x, z)
      
      if game.world.chunks[x][z].mesh.len > 0:
        var model = translate(identityMatrix4(), vec3(
          float32(x * ChunkSize),
          0,
          float32(z * ChunkSize)
        ))
        
        glUniformMatrix4fv(glGetUniformLocation(game.shader, "model"), 1, GL_FALSE, addr model[0][0])
        
        glBindVertexArray(game.world.chunks[x][z].vao)
        glDrawArrays(GL_TRIANGLES, 0, (game.world.chunks[x][z].mesh.len div 8).GLsizei)
  
  # Draw block in hand indicator (simplified)
  glfwSwapBuffers(game.window)
  glfwPollEvents()
  
  # Update nearby chunks
  let playerChunkX = floorDiv(int(game.player.pos.x), ChunkSize)
  let playerChunkZ = floorDiv(int(game.player.pos.z), ChunkSize)
  
  for x in -RenderDistance..RenderDistance:
    for z in -RenderDistance..RenderDistance:
      let chunkX = playerChunkX + x
      let chunkZ = playerChunkZ + z
      if chunkX notin -RenderDistance..RenderDistance or 
         chunkZ notin -RenderDistance..RenderDistance:
        generateChunk(game.world, chunkX, chunkZ)

# Main game loop
proc run(game: var Game) =
  game.lastTime = glfwGetTime()
  
  while glfwWindowShouldClose(game.window) == 0:
    let currentTime = glfwGetTime()
    game.deltaTime = float32(currentTime - game.lastTime)
    game.lastTime = currentTime
    
    updatePlayer(game)
    render(game)
    
    # Frame rate limiter
    if game.deltaTime < 1.0/60.0:
      sleep(int((1.0/60.0 - game.deltaTime) * 1000))

# Entry point
proc main() =
  var game = initGame()
  game.run()
  
  glfwDestroyWindow(game.window)
  glfwTerminate()

when isMainModule:
  main()