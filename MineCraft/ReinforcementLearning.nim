import std/[math, random, os, times, strformat, json, sequtils, tables]
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
  # RL Constants
  MaxEpisodes = 1000
  MaxStepsPerEpisode = 1000
  LearningRate = 0.001
  Gamma = 0.99  # Discount factor
  EpsilonStart = 1.0
  EpsilonEnd = 0.01
  EpsilonDecay = 0.995
  BatchSize = 32
  MemorySize = 10000
  UpdateTargetFreq = 100
  StateSize = 20
  ActionSize = 6  # Move: forward/back/left/right/jump/place

# Types (existing + new RL types)
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
    score: float
    inventory: array[BlockTypes, int]
  
  Camera = object
    pos, front, up, right: Vec3
    yaw, pitch: float32
  
  # RL Types
  Experience = object
    state: array[StateSize, float32]
    action: int
    reward: float32
    nextState: array[StateSize, float32]
    done: bool
  
  ReplayMemory = object
    buffer: seq[Experience]
    capacity: int
    position: int
  
  NeuralNetwork = object
    layers: seq[seq[seq[float32]]]  # weights and biases
    layerSizes: seq[int]
  
  DQNAgent = object
    policyNet: NeuralNetwork
    targetNet: NeuralNetwork
    memory: ReplayMemory
    epsilon: float32
    steps: int
    episodeRewards: seq[float]
  
  RLObservation = object
    playerPos: Vec3
    nearbyBlocks: array[27, tuple[typ: BlockType, dist: float32]]  # 3x3x3 area
    hasTarget: bool
    targetPos: Vec3
    timeAlive: int
    blocksMined: int
    blocksPlaced: int
  
  RLAgent = object
    dqn: DQNAgent
    observation: RLObservation
    currentState: array[StateSize, float32]
    lastAction: int
    lastReward: float32
    episodeStep: int
    totalReward: float
    training: bool
  
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
    # RL components
    rlAgent: RLAgent
    targetBlocks: seq[(int, int, int)]
    showRL: bool
    episodeCount: int

# Utility functions (existing)
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

# Neural Network implementation
proc initNeuralNetwork(layerSizes: seq[int]): NeuralNetwork =
  result.layerSizes = layerSizes
  result.layers = newSeq[seq[seq[float32]]](layerSizes.len - 1)
  
  for i in 0..<layerSizes.len - 1:
    let inputSize = layerSizes[i]
    let outputSize = layerSizes[i + 1]
    
    # Initialize weights (Xavier initialization)
    var weights = newSeq[seq[float32]](outputSize)
    for j in 0..<outputSize:
      weights[j] = newSeq[float32](inputSize)
      for k in 0..<inputSize:
        weights[j][k] = rand(1.0) * sqrt(2.0 / (inputSize + outputSize).float32) - 
                        sqrt(1.0 / (inputSize + outputSize).float32)
    
    # Initialize biases
    var biases = newSeq[float32](outputSize)
    for j in 0..<outputSize:
      biases[j] = rand(0.1) - 0.05
    
    result.layers[i] = weights
    result.layers[i].add(biases)  # Store biases as last row

proc forward(net: NeuralNetwork, input: seq[float32]): seq[float32] =
  var current = input
  
  for layerIdx in 0..<net.layers.len:
    let weights = net.layers[layerIdx][0..^2]  # All but last row
    let biases = net.layers[layerIdx][^1]      # Last row is biases
    
    var output = newSeq[float32](weights.len)
    
    for i in 0..<weights.len:
      var sum = biases[i]
      for j in 0..<current.len:
        sum += weights[i][j] * current[j]
      
      # ReLU activation for hidden layers, linear for output
      if layerIdx < net.layers.len - 1:
        output[i] = max(0.0, sum)
      else:
        output[i] = sum
    
    current = output
  
  return current

proc copyWeights(src: NeuralNetwork, dst: var NeuralNetwork) =
  for i in 0..<src.layers.len:
    for j in 0..<src.layers[i].len:
      for k in 0..<src.layers[i][j].len:
        dst.layers[i][j][k] = src.layers[i][j][k]

# Replay Memory
proc initReplayMemory(capacity: int): ReplayMemory =
  result.buffer = newSeq[Experience](capacity)
  result.capacity = capacity
  result.position = 0

proc push(memory: var ReplayMemory, exp: Experience) =
  memory.buffer[memory.position] = exp
  memory.position = (memory.position + 1) mod memory.capacity

proc sample(memory: ReplayMemory, batchSize: int): seq[Experience] =
  result = newSeq[Experience](batchSize)
  for i in 0..<batchSize:
    let idx = rand(memory.capacity - 1)
    result[i] = memory.buffer[idx]

# DQN Agent
proc initDQNAgent(stateSize, actionSize: int): DQNAgent =
  # Initialize neural networks with 2 hidden layers
  let layerSizes = @[stateSize, 64, 64, actionSize]
  result.policyNet = initNeuralNetwork(layerSizes)
  result.targetNet = initNeuralNetwork(layerSizes)
  result.copyWeights(result.policyNet, result.targetNet)
  
  result.memory = initReplayMemory(MemorySize)
  result.epsilon = EpsilonStart
  result.episodeRewards = @[]

proc act(agent: var DQNAgent, state: array[StateSize, float32]): int =
  # Epsilon-greedy action selection
  if rand(1.0) < agent.epsilon:
    result = rand(ActionSize - 1)
  else:
    let qValues = agent.policyNet.forward(state.toSeq)
    var bestAction = 0
    var bestValue = qValues[0]
    for i in 1..<qValues.len:
      if qValues[i] > bestValue:
        bestValue = qValues[i]
        bestAction = i
    result = bestAction

proc store(agent: var DQNAgent, state: array[StateSize, float32], action: int, 
           reward: float32, nextState: array[StateSize, float32], done: bool) =
  let exp = Experience(
    state: state,
    action: action,
    reward: reward,
    nextState: nextState,
    done: done
  )
  agent.memory.push(exp)

proc learn(agent: var DQNAgent) =
  if agent.memory.position < BatchSize:
    return
  
  let batch = agent.memory.sample(BatchSize)
  
  for exp in batch:
    # Compute target Q value
    let nextQ = agent.targetNet.forward(exp.nextState.toSeq)
    var maxNextQ = nextQ[0]
    for i in 1..<nextQ.len:
      if nextQ[i] > maxNextQ:
        maxNextQ = nextQ[i]
    
    let target = if exp.done: exp.reward
                 else: exp.reward + Gamma * maxNextQ
    
    # Get current Q values
    var currentQ = agent.policyNet.forward(exp.state.toSeq)
    let currentTarget = currentQ[exp.action]
    
    # Simple gradient update (in practice use optimizer like Adam)
    let error = target - currentTarget
    # Update weights for this action (simplified)
    # In production, use proper backpropagation
    
    agent.policyNet.layers[^1][exp.action][0] += LearningRate * error * currentQ[exp.action]
  
  # Update epsilon
  agent.epsilon = max(EpsilonEnd, agent.epsilon * EpsilonDecay)
  
  # Update target network periodically
  agent.steps += 1
  if agent.steps mod UpdateTargetFreq == 0:
    copyWeights(agent.policyNet, agent.targetNet)

# RL Agent
proc initRLAgent(): RLAgent =
  result.dqn = initDQNAgent(StateSize, ActionSize)
  result.training = true
  result.totalReward = 0

proc observeEnvironment(game: Game): RLObservation =
  result.playerPos = game.player.pos
  result.timeAlive = game.rlAgent.episodeStep
  result.blocksMined = game.player.inventory[0]  # Simple metric
  result.blocksPlaced = game.player.inventory[1]
  
  # Scan nearby blocks (3x3x3 area around player)
  var idx = 0
  for x in -1..1:
    for y in -1..1:
      for z in -1..1:
        if idx < 27:
          let blockX = int(game.player.pos.x) + x
          let blockY = int(game.player.pos.y) + y
          let blockZ = int(game.player.pos.z) + z
          
          let cx = floorDiv(blockX, ChunkSize)
          let cz = floorDiv(blockZ, ChunkSize)
          
          if cx in -RenderDistance..RenderDistance and 
             cz in -RenderDistance..RenderDistance and
             blockY in 0..<ChunkSize:
            let lx = blockX mod ChunkSize
            let lz = blockZ mod ChunkSize
            let block = game.world.chunks[cx][cz].blocks[lx][blockY][lz]
            
            let dx = blockX.float32 - game.player.pos.x
            let dy = blockY.float32 - game.player.pos.y
            let dz = blockZ.float32 - game.player.pos.z
            let dist = sqrt(dx*dx + dy*dy + dz*dz)
            
            result.nearbyBlocks[idx] = (block.typ, dist)
          else:
            result.nearbyBlocks[idx] = (btAir, 100.0)
          
          idx += 1
  
  # Check for target blocks (e.g., wood)
  result.hasTarget = false
  for target in game.targetBlocks:
    let dx = target[0].float32 - game.player.pos.x
    let dy = target[1].float32 - game.player.pos.y
    let dz = target[2].float32 - game.player.pos.z
    let dist = sqrt(dx*dx + dy*dy + dz*dz)
    
    if dist < 10.0:
      result.hasTarget = true
      result.targetPos = vec3(target[0].float32, target[1].float32, target[2].float32)
      break

proc encodeState(obs: RLObservation): array[StateSize, float32] =
  var idx = 0
  
  # Player position (3)
  result[idx] = obs.playerPos.x / 100.0; idx += 1
  result[idx] = obs.playerPos.y / 100.0; idx += 1
  result[idx] = obs.playerPos.z / 100.0; idx += 1
  
  # Nearby blocks (27 * 2 = 54, but we'll compress to 15)
  for i in 0..<15:
    if i < obs.nearbyBlocks.len:
      result[idx] = obs.nearbyBlocks[i].typ.float32 / 4.0; idx += 1
      result[idx] = obs.nearbyBlocks[i].dist / 10.0; idx += 1
    else:
      result[idx] = 0; idx += 1
      result[idx] = 0; idx += 1
  
  # Has target (1)
  result[idx] = if obs.hasTarget: 1.0 else: 0.0; idx += 1
  
  # Target position relative (3)
  if obs.hasTarget:
    result[idx] = (obs.targetPos.x - obs.playerPos.x) / 10.0; idx += 1
    result[idx] = (obs.targetPos.y - obs.playerPos.y) / 10.0; idx += 1
    result[idx] = (obs.targetPos.z - obs.playerPos.z) / 10.0; idx += 1
  else:
    result[idx] = 0; idx += 1
    result[idx] = 0; idx += 1
    result[idx] = 0; idx += 1
  
  # Stats (2)
  result[idx] = obs.timeAlive.float32 / 1000.0; idx += 1
  result[idx] = obs.blocksMined.float32 / 100.0; idx += 1

proc calculateReward(prevObs, currentObs: RLObservation, action: int): float32 =
  result = -0.01  # Small penalty per step to encourage efficiency
  
  # Reward for moving toward target
  if currentObs.hasTarget:
    let prevDist = if prevObs.hasTarget:
      sqrt((prevObs.targetPos.x - prevObs.playerPos.x)^2 + 
           (prevObs.targetPos.y - prevObs.playerPos.y)^2 + 
           (prevObs.targetPos.z - prevObs.playerPos.z)^2)
    else: 100.0
    
    let currentDist = sqrt((currentObs.targetPos.x - currentObs.playerPos.x)^2 + 
                           (currentObs.targetPos.y - currentObs.playerPos.y)^2 + 
                           (currentObs.targetPos.z - currentObs.playerPos.z)^2)
    
    if currentDist < prevDist:
      result += 0.05  # Reward for moving closer
  
  # Reward for mining blocks
  if currentObs.blocksMined > prevObs.blocksMined:
    result += 1.0
  
  # Reward for placing blocks
  if currentObs.blocksPlaced > prevObs.blocksPlaced:
    result += 0.5
  
  # Big reward for reaching target
  if currentObs.hasTarget and currentDist < 2.0:
    result += 10.0

proc executeAction(agent: var RLAgent, action: int, game: var Game) =
  let speed = PlayerSpeed * game.deltaTime
  
  case action
  of 0: # Move forward
    game.player.pos = game.player.pos + game.camera.front * speed
  of 1: # Move backward
    game.player.pos = game.player.pos - game.camera.front * speed
  of 2: # Move left
    game.player.pos = game.player.pos - game.camera.right * speed
  of 3: # Move right
    game.player.pos = game.player.pos + game.camera.right * speed
  of 4: # Jump
    if game.player.onGround:
      game.player.velocity.y = JumpStrength
  of 5: # Place block
    if game.player.inventory[1] > 0:  # Have blocks to place
      let placeX = int(game.player.pos.x) + int(game.camera.front.x * 2)
      let placeY = int(game.player.pos.y) + int(game.camera.front.y * 2)
      let placeZ = int(game.player.pos.z) + int(game.camera.front.z * 2)
      
      let placeCx = floorDiv(placeX, ChunkSize)
      let placeCz = floorDiv(placeZ, ChunkSize)
      
      if placeCx in -RenderDistance..RenderDistance and 
         placeCz in -RenderDistance..RenderDistance and
         placeY in 0..<ChunkSize:
        let placeLx = placeX mod ChunkSize
        let placeLz = placeZ mod ChunkSize
        
        if not game.world.chunks[placeCx][placeCz].blocks[placeLx][placeY][placeLz].active:
          game.world.chunks[placeCx][placeCz].blocks[placeLx][placeY][placeLz].active = true
          game.world.chunks[placeCx][placeCz].blocks[placeLx][placeY][placeLz].typ = btGrass
          game.world.chunks[placeCx][placeCz].dirty = true
          game.player.inventory[1] -= 1
  else:
    discard

proc updateRL(game: var Game) =
  if not game.rlAgent.training:
    return
  
  # Observe current environment
  let currentObs = observeEnvironment(game)
  
  # Encode state
  let currentState = encodeState(currentObs)
  
  # Store experience if not first step
  if game.rlAgent.episodeStep > 0:
    let reward = calculateReward(game.rlAgent.observation, currentObs, game.rlAgent.lastAction)
    game.rlAgent.dqn.store(game.rlAgent.currentState, game.rlAgent.lastAction, 
                           reward, currentState, false)
    game.rlAgent.totalReward += reward
  
  # Select action
  let action = game.rlAgent.dqn.act(currentState)
  
  # Execute action
  executeAction(game.rlAgent, action, game)
  
  # Learn from experiences
  game.rlAgent.dqn.learn()
  
  # Update state
  game.rlAgent.observation = currentObs
  game.rlAgent.currentState = currentState
  game.rlAgent.lastAction = action
  game.rlAgent.episodeStep += 1
  
  # Check episode end
  if game.rlAgent.episodeStep >= MaxStepsPerEpisode or currentObs.blocksMined > 10:
    endEpisode(game)

proc endEpisode(game: var Game) =
  echo &"Episode {game.episodeCount} finished with reward: {game.rlAgent.totalReward:.2f}"
  game.rlAgent.dqn.episodeRewards.add(game.rlAgent.totalReward)
  
  # Reset player
  game.player.pos = vec3(0, 40, 0)
  game.player.velocity = vec3(0, 0, 0)
  game.player.inventory = [5, 0, 0, 0]  # Start with 5 blocks
  
  # Generate new targets
  game.targetBlocks = @[]
  for i in 0..<5:
    let x = rand(-20..20)
    let z = rand(-20..20)
    let y = generateHeight(x, z) + 1
    game.targetBlocks.add((x, y, z))
  
  # Reset RL agent
  game.rlAgent.episodeStep = 0
  game.rlAgent.totalReward = 0
  game.rlAgent.observation = observeEnvironment(game)
  game.rlAgent.currentState = encodeState(game.rlAgent.observation)
  
  game.episodeCount += 1
  
  # Decay epsilon
  if game.episodeCount mod 10 == 0:
    game.rlAgent.dqn.epsilon = max(EpsilonEnd, game.rlAgent.dqn.epsilon * 0.99)

# Modified game initialization
proc initGame(): Game =
  randomize()
  
  # Initialize GLFW (same as before)
  if glfwInit() == 0:
    quit("Failed to initialize GLFW")
  
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3)
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3)
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)
  
  result.window = glfwCreateWindow(WindowWidth, WindowHeight, "NimCraft RL", nil, nil)
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
  result.player.inventory = [5, 0, 0, 0]  # Start with 5 blocks
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
  
  # Initialize RL components
  result.rlAgent = initRLAgent()
  result.targetBlocks = @[]
  for i in 0..<5:
    let x = rand(-20..20)
    let z = rand(-20..20)
    let y = generateHeight(x, z) + 1
    result.targetBlocks.add((x, y, z))
  
  result.showRL = true
  result.episodeCount = 0
  
  # Initial observation
  result.rlAgent.observation = observeEnvironment(result)
  result.rlAgent.currentState = encodeState(result.rlAgent.observation)

# Modified render function to show RL info
proc render(game: var Game) =
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  
  glUseProgram(game.shader)
  
  # Set uniforms (same as before)
  var view = identityMatrix4()
  view = lookAt(game.camera.pos, game.camera.pos + game.camera.front, vec3(0, 1, 0))
  
  var projection = perspective(45.0, WindowWidth / WindowHeight, 0.1, 1000.0)
  
  glUniformMatrix4fv(glGetUniformLocation(game.shader, "view"), 1, GL_FALSE, addr view[0][0])
  glUniformMatrix4fv(glGetUniformLocation(game.shader, "projection"), 1, GL_FALSE, addr projection[0][0])
  glUniform3f(glGetUniformLocation(game.shader, "lightPos"), 100, 100, 100)
  glUniform3f(glGetUniformLocation(game.shader, "viewPos"), game.camera.pos.x, game.camera.pos.y, game.camera.pos.z)
  glUniform3f(glGetUniformLocation(game.shader, "lightColor"), 1, 1, 1)
  glUniform3f(glGetUniformLocation(game.shader, "objectColor"), 0.8, 0.8, 0.8)
  
  # Render chunks (same as before)
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
  
  # Render target blocks (highlight them)
  glUseProgram(0)
  glDisable(GL_TEXTURE_2D)
  glColor3f(1, 0, 0)
  glBegin(GL_LINES)
  for target in game.targetBlocks:
    glVertex3f(target[0].float32, target[1].float32, target[2].float32)
    glVertex3f(target[0].float32, target[1].float32 + 2, target[2].float32)
  glEnd()
  
  # Render RL info overlay
  if game.showRL:
    # Simple text rendering would go here
    # For now, just print to console occasionally
    if game.episodeCount mod 10 == 0 and game.rlAgent.episodeStep == 0:
      echo &"Episode {game.episodeCount}, Epsilon: {game.rlAgent.dqn.epsilon:.3f}, " &
           &"Avg Reward: {game.rlAgent.totalReward / max(1, game.rlAgent.episodeStep).float:.2f}"
  
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

# Modified key callback for RL controls
proc keyCallback(window: GLFWwindow, key, scancode, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  if key == GLFW_KEY_ESCAPE and action == GLFW_PRESS:
    game.mouseCaptured = not game.mouseCaptured
    glfwSetInputMode(window, GLFW_CURSOR, 
                     if game.mouseCaptured: GLFW_CURSOR_DISABLED else: GLFW_CURSOR_NORMAL)
  elif key == GLFW_KEY_F3 and action == GLFW_PRESS:
    game.wireframe = not game.wireframe
    glPolygonMode(GL_FRONT_AND_BACK, if game.wireframe: GL_LINE else: GL_FILL)
  elif key == GLFW_KEY_R and action == GLFW_PRESS:
    game.rlAgent.training = not game.rlAgent.training
    echo &"RL Training: {game.rlAgent.training}"
  elif key == GLFW_KEY_P and action == GLFW_PRESS:
    # Print training stats
    let rewards = game.rlAgent.dqn.episodeRewards
    if rewards.len > 0:
      let avgReward = sum(rewards) / rewards.len.float
      echo &"Training Stats - Episodes: {rewards.len}, Avg Reward: {avgReward:.2f}, " &
           &"Best: {max(rewards):.2f}, Epsilon: {game.rlAgent.dqn.epsilon:.3f}"
  elif key in [GLFW_KEY_1, GLFW_KEY_2, GLFW_KEY_3, GLFW_KEY_4] and action == GLFW_PRESS:
    game.blockInHand = BlockType(key.int - GLFW_KEY_1.int + 1)

# Modified main game loop
proc run(game: var Game) =
  game.lastTime = glfwGetTime()
  
  while glfwWindowShouldClose(game.window) == 0:
    let currentTime = glfwGetTime()
    game.deltaTime = float32(currentTime - game.lastTime)
    game.lastTime = currentTime
    
    # Update player (manual control when not training)
    if not game.rlAgent.training or not game.mouseCaptured:
      updatePlayer(game)
    else:
      # RL agent controls
      game.updateRL()
      # Update camera to follow player
      game.camera.pos = game.player.pos
    
    render(game)
    
    # Frame rate limiter
    if game.deltaTime < 1.0/60.0:
      sleep(int((1.0/60.0 - game.deltaTime) * 1000))

# Save/Load model
proc saveModel(agent: DQNAgent, filename: string) =
  var data: seq[seq[seq[float32]]] = @[]
  for layer in agent.policyNet.layers:
    data.add(layer)
  
  let f = open(filename, fmWrite)
  f.write($(%data))
  f.close()
  echo "Model saved to ", filename

proc loadModel(agent: var DQNAgent, filename: string) =
  if not fileExists(filename):
    echo "Model file not found: ", filename
    return
  
  let f = open(filename, fmRead)
  let jsonData = parseJson(f.readAll())
  f.close()
  
  for i in 0..<jsonData.len:
    for j in 0..<jsonData[i].len:
      for k in 0..<jsonData[i][j].len:
        agent.policyNet.layers[i][j][k] = jsonData[i][j][k].getFloat().float32
  
  copyWeights(agent.policyNet, agent.targetNet)
  echo "Model loaded from ", filename

# Entry point
proc main() =
  var game = initGame()
  
  # Try to load pre-trained model
  if fileExists("dqn_model.json"):
    loadModel(game.rlAgent.dqn, "dqn_model.json")
  
  game.run()
  
  # Save model on exit
  saveModel(game.rlAgent.dqn, "dqn_model.json")
  
  glfwDestroyWindow(game.window)
  glfwTerminate()

when isMainModule:
  main()