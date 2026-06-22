# Add these imports at the top
import httpclient, htmlparser, xmltree, strtabs, cgi, uri, re, asyncdispatch, asyncnet
import browsers  # For opening external browser

# Add to constants
const
  # Web Search
  MaxSearchHistory = 50
  MaxBookmarks = 100
  SearchEngineGoogle = "https://www.google.com/search?q="
  SearchEngineDuckDuckGo = "https://html.duckduckgo.com/html/?q="
  SearchEngineWikipedia = "https://en.wikipedia.org/wiki/"
  UserAgent = "Mozilla/5.0 (NimCraft Minecraft Clone; WebSearch Module)"

# Add to types
type
  # Web Search Types
  WebSearchEngine* = enum
    wseGoogle
    wseDuckDuckGo
    wseWikipedia
    wseCustom
  
  WebSearchResult* = object
    title*: string
    url*: string
    snippet*: string
    favicon*: string
  
  WebPage* = object
    url*: string
    title*: string
    content*: string
    html*: string
    loaded*: bool
    loadTime*: float
  
  WebHistoryEntry* = object
    url*: string
    title*: string
    timestamp*: float
  
  WebBookmark* = object
    url*: string
    title*: string
    category*: string
  
  WebSearchTab* = object
    id*: int
    title*: string
    url*: string
    history*: seq[WebHistoryEntry]
    currentPosition*: int
    isLoading*: bool
    progress*: float
    page*: WebPage
    searchResults*: seq[WebSearchResult]
  
  WebSearchGui* = ref object of GuiElement
    tabs*: seq[WebSearchTab]
    currentTab*: int
    addressBar*: TextBox
    searchButton*: Button
    backButton*: Button
    forwardButton*: Button
    refreshButton*: Button
    bookmarkButton*: Button
    bookmarks*: seq[WebBookmark]
    searchEngine*: WebSearchEngine
    customSearchUrl*: string
    history*: seq[WebHistoryEntry]
    isLoading*: bool
    statusText*: string
  
  # Add to Game type
  Game* = ref object
    # ... existing fields ...
    webSearch*: WebSearchGui
    webSearchVisible*: bool
    httpClient*: AsyncHttpClient

# ==================== Web Search Functions ====================

proc initWebSearchGui*(): WebSearchGui =
  new(result)
  result.tabs = @[]
  result.currentTab = -1
  result.bookmarks = @[]
  result.history = @[]
  result.searchEngine = wseDuckDuckGo
  result.customSearchUrl = ""
  result.isLoading = false
  
  # Create new tab
  result.newTab("about:blank", "New Tab")

proc newTab*(gui: WebSearchGui, url: string, title: string = "New Tab") =
  let tab = WebSearchTab(
    id: gui.tabs.len,
    title: title,
    url: url,
    history: @[],
    currentPosition: -1,
    isLoading: false,
    progress: 0,
    page: WebPage(url: url, title: title, loaded: false)
  )
  gui.tabs.add(tab)
  gui.currentTab = gui.tabs.len - 1
  
  if url != "about:blank" and url != "":
    gui.navigateToTab(gui.currentTab, url)

proc navigateToTab*(gui: WebSearchGui, tabIndex: int, url: string) {.async.} =
  if tabIndex < 0 or tabIndex >= gui.tabs.len:
    return
  
  var tab = addr gui.tabs[tabIndex]
  tab.isLoading = true
  tab.progress = 0
  tab.url = url
  tab.title = "Loading..."
  
  # Add to history
  let historyEntry = WebHistoryEntry(
    url: url,
    title: tab.title,
    timestamp: epochTime()
  )
  tab.history.add(historyEntry)
  tab.currentPosition = tab.history.len - 1
  
  # Add to global history
  gui.history.add(historyEntry)
  if gui.history.len > MaxSearchHistory:
    gui.history.delete(0)
  
  try:
    # Perform web search or load URL
    if url.startsWith("search:"):
      let query = url[7..^1]  # Remove "search:" prefix
      await gui.performSearch(tabIndex, query)
    else:
      await gui.loadUrl(tabIndex, url)
  except:
    tab.page.title = "Error loading page"
    tab.page.content = "Failed to load: " & getCurrentExceptionMsg()
    gui.statusText = "Error: " & getCurrentExceptionMsg()
  
  tab.isLoading = false

proc performSearch*(gui: WebSearchGui, tabIndex: int, query: string) {.async.} =
  var tab = addr gui.tabs[tabIndex]
  tab.title = &"Searching: {query}"
  tab.searchResults = @[]
  
  let encodedQuery = encodeUrl(query)
  var searchUrl: string
  
  case gui.searchEngine
  of wseGoogle:
    searchUrl = SearchEngineGoogle & encodedQuery
  of wseDuckDuckGo:
    searchUrl = SearchEngineDuckDuckGo & encodedQuery
  of wseWikipedia:
    searchUrl = SearchEngineWikipedia & encodedQuery.replace(" ", "_")
  of wseCustom:
    searchUrl = gui.customSearchUrl.replace("%s", encodedQuery)
  
  try:
    let client = newAsyncHttpClient(userAgent=UserAgent)
    let response = await client.get(searchUrl)
    let html = await response.body
    
    # Parse search results based on search engine
    var results: seq[WebSearchResult] = @[]
    
    case gui.searchEngine
    of wseGoogle:
      # Parse Google results (simplified)
      let doc = parseHtml(html)
      for elem in doc.findAll("div"):  # Would need proper CSS selectors
        if elem.attr("class") == "g":
          var result: WebSearchResult
          let titleElem = elem.find("h3")
          if titleElem != nil:
            result.title = titleElem.innerText()
          let linkElem = elem.find("a")
          if linkElem != nil:
            result.url = linkElem.attr("href")
          let snippetElem = elem.find("span", class="st")
          if snippetElem != nil:
            result.snippet = snippetElem.innerText()
          if result.title != "":
            results.add(result)
    
    of wseDuckDuckGo:
      # Parse DuckDuckGo results
      let doc = parseHtml(html)
      for elem in doc.findAll("div", class="result"):
        var result: WebSearchResult
        let titleElem = elem.find("a", class="result__a")
        if titleElem != nil:
          result.title = titleElem.innerText()
          result.url = titleElem.attr("href")
        let snippetElem = elem.find("a", class="result__snippet")
        if snippetElem != nil:
          result.snippet = snippetElem.innerText()
        if result.title != "":
          results.add(result)
    
    of wseWikipedia:
      # Wikipedia is direct page, not search results
      tab.page.title = query
      tab.page.content = html
      tab.page.loaded = true
      tab.title = query
      return
    
    of wseCustom:
      # Custom search engine - assume JSON response
      try:
        let json = parseJson(html)
        # Parse based on expected format
        if json.hasKey("items"):
          for item in json["items"]:
            var result: WebSearchResult
            result.title = item{"title"}.getStr("")
            result.url = item{"link"}.getStr("")
            result.snippet = item{"snippet"}.getStr("")
            results.add(result)
      except:
        # Fallback to plain HTML parsing
        let doc = parseHtml(html)
        for elem in doc.findAll("a"):
          if elem.attr("href").startsWith("http"):
            var result: WebSearchResult
            result.title = elem.innerText()
            result.url = elem.attr("href")
            results.add(result)
    
    tab.searchResults = results
    tab.title = &"Search results: {query}"
    gui.statusText = &"Found {results.len} results"
    
  except:
    gui.statusText = "Search failed: " & getCurrentExceptionMsg()

proc loadUrl*(gui: WebSearchGui, tabIndex: int, url: string) {.async.} =
  var tab = addr gui.tabs[tabIndex]
  
  # Ensure URL has protocol
  var fullUrl = url
  if not fullUrl.startsWith("http://") and not fullUrl.startsWith("https://"):
    fullUrl = "http://" & fullUrl
  
  try:
    let client = newAsyncHttpClient(userAgent=UserAgent, timeout=5000)
    let response = await client.get(fullUrl)
    
    # Update progress
    tab.progress = 0.5
    
    let html = await response.body
    let doc = parseHtml(html)
    
    # Extract title
    let titleTag = doc.find("title")
    tab.page.title = if titleTag != nil: titleTag.innerText() else: fullUrl
    tab.page.content = html
    tab.page.html = html
    tab.page.loaded = true
    tab.page.loadTime = epochTime()
    tab.title = tab.page.title
    
    # Update history title
    if tab.history.len > 0:
      tab.history[tab.history.len - 1].title = tab.page.title
    
    tab.progress = 1.0
    gui.statusText = &"Loaded: {tab.page.title}"
    
  except:
    tab.page.title = "Error"
    tab.page.content = "Failed to load: " & getCurrentExceptionMsg()
    gui.statusText = "Error loading page"

proc addBookmark*(gui: WebSearchGui, url, title, category: string = "General") =
  let bookmark = WebBookmark(
    url: url,
    title: title,
    category: category
  )
  gui.bookmarks.add(bookmark)
  if gui.bookmarks.len > MaxBookmarks:
    gui.bookmarks.delete(0)

proc removeBookmark*(gui: WebSearchGui, index: int) =
  if index >= 0 and index < gui.bookmarks.len:
    gui.bookmarks.delete(index)

proc goBack*(gui: WebSearchGui) =
  if gui.currentTab < 0: return
  var tab = addr gui.tabs[gui.currentTab]
  if tab.currentPosition > 0:
    tab.currentPosition -= 1
    let entry = tab.history[tab.currentPosition]
    asyncCheck gui.navigateToTab(gui.currentTab, entry.url)

proc goForward*(gui: WebSearchGui) =
  if gui.currentTab < 0: return
  var tab = addr gui.tabs[gui.currentTab]
  if tab.currentPosition < tab.history.len - 1:
    tab.currentPosition += 1
    let entry = tab.history[tab.currentPosition]
    asyncCheck gui.navigateToTab(gui.currentTab, entry.url)

proc refresh*(gui: WebSearchGui) =
  if gui.currentTab < 0: return
  let tab = gui.tabs[gui.currentTab]
  asyncCheck gui.navigateToTab(gui.currentTab, tab.url)

# ==================== Web Search GUI ====================

proc createWebSearchGui*(game: Game): WebSearchGui =
  result = initWebSearchGui()
  
  # Create address bar
  result.addressBar = newTextBox(120, 10, 400, 30, "Enter URL or search query...")
  result.addressBar.onKeyPress = proc(key: char) =
    if key == '\r':  # Enter key
      let text = result.addressBar.text
      if text.startsWith("http://") or text.startsWith("https://") or text.contains("."):
        asyncCheck result.navigateToTab(result.currentTab, text)
      else:
        asyncCheck result.navigateToTab(result.currentTab, "search:" & text)
  
  # Create navigation buttons
  result.backButton = newButton("←", 20, 10, 30, 30, proc() =
    result.goBack()
  )
  
  result.forwardButton = newButton("→", 55, 10, 30, 30, proc() =
    result.goForward()
  )
  
  result.refreshButton = newButton("↻", 90, 10, 30, 30, proc() =
    result.refresh()
  )
  
  result.searchButton = newButton("Search", 530, 10, 80, 30, proc() =
    let text = result.addressBar.text
    if text.len > 0:
      asyncCheck result.navigateToTab(result.currentTab, "search:" & text)
  )
  
  result.bookmarkButton = newButton("★", 620, 10, 30, 30, proc() =
    if result.currentTab >= 0:
      let tab = result.tabs[result.currentTab]
      result.addBookmark(tab.url, tab.title)
  )

proc renderWebSearch*(game: Game) =
  if not game.webSearchVisible or game.webSearch == nil:
    return
  
  let gui = game.webSearch
  
  # Setup orthographic projection for web search
  glUseProgram(game.shaders["gui"])
  var projection = ortho(0.0, WindowWidth.float32, WindowHeight.float32, 0.0, -1.0, 1.0)
  glUniformMatrix4fv(glGetUniformLocation(game.shaders["gui"], "projection"), 
                     1, GL_FALSE, addr projection[0][0])
  glUniform1i(glGetUniformLocation(game.shaders["gui"], "guiMode"), 1)
  
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  
  # Draw web search background
  glBegin(GL_QUADS)
  glColor4f(0.1, 0.1, 0.1, 0.95)
  glVertex2f(0, 0)
  glVertex2f(WindowWidth.float32, 0)
  glVertex2f(WindowWidth.float32, WindowHeight.float32)
  glVertex2f(0, WindowHeight.float32)
  glEnd()
  
  # Draw toolbar background
  glBegin(GL_QUADS)
  glColor4f(0.2, 0.2, 0.2, 1)
  glVertex2f(0, 0)
  glVertex2f(WindowWidth.float32, 0)
  glVertex2f(WindowWidth.float32, 50)
  glVertex2f(0, 50)
  glEnd()
  
  # Render navigation buttons
  renderButton(gui.backButton)
  renderButton(gui.forwardButton)
  renderButton(gui.refreshButton)
  renderButton(gui.searchButton)
  renderButton(gui.bookmarkButton)
  
  # Render address bar
  renderTextBox(gui.addressBar)
  
  # Render tabs
  var tabX = 10
  for i, tab in gui.tabs:
    let tabWidth = 150
    let tabHeight = 30
    let tabY = 55
    
    # Tab background
    glBegin(GL_QUADS)
    if i == gui.currentTab:
      glColor4f(0.3, 0.3, 0.3, 1)
    else:
      glColor4f(0.15, 0.15, 0.15, 1)
    glVertex2f(tabX.float32, tabY.float32)
    glVertex2f((tabX + tabWidth).float32, tabY.float32)
    glVertex2f((tabX + tabWidth).float32, (tabY + tabHeight).float32)
    glVertex2f(tabX.float32, (tabY + tabHeight).float32)
    glEnd()
    
    # Tab border
    glBegin(GL_LINE_LOOP)
    glColor4f(0.5, 0.5, 0.5, 1)
    glVertex2f(tabX.float32, tabY.float32)
    glVertex2f((tabX + tabWidth).float32, tabY.float32)
    glVertex2f((tabX + tabWidth).float32, (tabY + tabHeight).float32)
    glVertex2f(tabX.float32, (tabY + tabHeight).float32)
    glEnd()
    
    # Tab title
    glRasterPos2f((tabX + 5).float32, (tabY + 20).float32)
    glColor4f(1, 1, 1, 1)
    var displayTitle = tab.title
    if displayTitle.len > 20:
      displayTitle = displayTitle[0..17] & "..."
    for c in displayTitle:
      glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
    
    # Close button
    if i > 0:  # Can't close first tab
      glRasterPos2f((tabX + tabWidth - 15).float32, (tabY + 20).float32)
      glColor4f(1, 0.3, 0.3, 1)
      glutBitmapCharacter(GLUT_BITMAP_8_BY_13, 'x'.int32)
    
    tabX += tabWidth + 5
  
  # New tab button
  glBegin(GL_QUADS)
  glColor4f(0.15, 0.15, 0.15, 1)
  glVertex2f(tabX.float32, 55.float32)
  glVertex2f((tabX + 30).float32, 55.float32)
  glVertex2f((tabX + 30).float32, 85.float32)
  glVertex2f(tabX.float32, 85.float32)
  glEnd()
  
  glRasterPos2f((tabX + 10).float32, 70.float32)
  glColor4f(1, 1, 1, 1)
  glutBitmapCharacter(GLUT_BITMAP_8_BY_13, '+'.int32)
  
  # Render current tab content
  if gui.currentTab >= 0 and gui.currentTab < gui.tabs.len:
    let tab = gui.tabs[gui.currentTab]
    
    if tab.isLoading:
      # Show loading indicator
      glBegin(GL_QUADS)
      glColor4f(0, 0.5, 1, 0.3)
      glVertex2f(10, 95)
      glVertex2f(10 + tab.progress * (WindowWidth - 20).float32, 95)
      glVertex2f(10 + tab.progress * (WindowWidth - 20).float32, 100)
      glVertex2f(10, 100)
      glEnd()
      
      glRasterPos2f(10, 120)
      glColor4f(1, 1, 1, 1)
      let loadingText = "Loading: " & tab.url
      for c in loadingText:
        glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
    
    elif tab.searchResults.len > 0:
      # Render search results
      var y = 120
      for i, result in tab.searchResults:
        # Result title
        glRasterPos2f(20, y.float32)
        glColor4f(0.3, 0.7, 1, 1)
        var title = result.title
        if title.len > 80:
          title = title[0..77] & "..."
        for c in title:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
        
        # Result URL
        glRasterPos2f(20, (y + 15).float32)
        glColor4f(0, 1, 0, 0.7)
        var url = result.url
        if url.len > 80:
          url = url[0..77] & "..."
        for c in url:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
        
        # Result snippet
        glRasterPos2f(20, (y + 30).float32)
        glColor4f(1, 1, 1, 0.8)
        var snippet = result.snippet
        if snippet.len > 100:
          snippet = snippet[0..97] & "..."
        for c in snippet:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
        
        y += 60
        if y > WindowHeight - 100:
          break
    
    elif tab.page.loaded:
      # Render web page content (simplified)
      glRasterPos2f(20, 120)
      glColor4f(1, 1, 1, 1)
      
      # Simple text rendering of page content
      var text = tab.page.content
      # Strip HTML tags for display
      text = text.replace(re"<[^>]*>", "")
      
      var y = 120
      var line = ""
      for word in text.split():
        if (line & " " & word).len > 80:
          for c in line:
            glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
          glRasterPos2f(20, (y + 15).float32)
          line = word
          y += 15
        else:
          if line.len > 0:
            line &= " "
          line &= word
        
        if y > WindowHeight - 50:
          break
      
      if line.len > 0:
        for c in line:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
    
    else:
      # Render home page
      glRasterPos2f(20, 120)
      glColor4f(1, 1, 1, 1)
      let homeText = "Welcome to NimCraft Web Search!\n\n" &
                    "Enter a URL or search query in the address bar above.\n" &
                    "Examples:\n" &
                    "  - https://nim-lang.org\n" &
                    "  - search:nim programming language\n" &
                    "  - wikipedia:Nim (programming language)\n\n" &
                    "Bookmarks:"
      for line in homeText.split('\n'):
        for c in line:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
        glRasterPos2f(20, (y + 15).float32)
        y += 15
      
      # Show bookmarks
      for bookmark in gui.bookmarks:
        glRasterPos2f(30, y.float32)
        glColor4f(0.3, 0.7, 1, 1)
        let displayText = &"★ {bookmark.title} - {bookmark.url}"
        for c in displayText:
          glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
        y += 15
  
  # Status bar
  glBegin(GL_QUADS)
  glColor4f(0.15, 0.15, 0.15, 1)
  glVertex2f(0, WindowHeight - 25)
  glVertex2f(WindowWidth.float32, WindowHeight - 25)
  glVertex2f(WindowWidth.float32, WindowHeight.float32)
  glVertex2f(0, WindowHeight.float32)
  glEnd()
  
  glRasterPos2f(10, WindowHeight - 12)
  glColor4f(0.7, 0.7, 0.7, 1)
  for c in gui.statusText:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  glEnable(GL_DEPTH_TEST)

proc renderButton*(btn: Button) =
  let (x, y, w, h) = btn.bounds
  
  # Button background
  glBegin(GL_QUADS)
  if btn.state == bsPressed:
    glColor4f(0.4, 0.4, 0.4, 1)
  elif btn.state == bsHovered:
    glColor4f(0.35, 0.35, 0.35, 1)
  else:
    glColor4f(0.25, 0.25, 0.25, 1)
  glVertex2f(x.float32, y.float32)
  glVertex2f((x + w).float32, y.float32)
  glVertex2f((x + w).float32, (y + h).float32)
  glVertex2f(x.float32, (y + h).float32)
  glEnd()
  
  # Button border
  glBegin(GL_LINE_LOOP)
  glColor4f(0.5, 0.5, 0.5, 1)
  glVertex2f(x.float32, y.float32)
  glVertex2f((x + w).float32, y.float32)
  glVertex2f((x + w).float32, (y + h).float32)
  glVertex2f(x.float32, (y + h).float32)
  glEnd()
  
  # Button text
  glRasterPos2f((x + w div 2 - btn.text.len * 4).float32, (y + h div 2 + 5).float32)
  glColor4f(1, 1, 1, 1)
  for c in btn.text:
    glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)

proc renderTextBox*(tb: TextBox) =
  let (x, y, w, h) = tb.bounds
  
  # Textbox background
  glBegin(GL_QUADS)
  glColor4f(0.15, 0.15, 0.15, 1)
  glVertex2f(x.float32, y.float32)
  glVertex2f((x + w).float32, y.float32)
  glVertex2f((x + w).float32, (y + h).float32)
  glVertex2f(x.float32, (y + h).float32)
  glEnd()
  
  # Textbox border
  glBegin(GL_LINE_LOOP)
  if tb.focused:
    glColor4f(0.3, 0.7, 1, 1)
  else:
    glColor4f(0.5, 0.5, 0.5, 1)
  glVertex2f(x.float32, y.float32)
  glVertex2f((x + w).float32, y.float32)
  glVertex2f((x + w).float32, (y + h).float32)
  glVertex2f(x.float32, (y + h).float32)
  glEnd()
  
  # Text
  glRasterPos2f((x + 5).float32, (y + h div 2 + 5).float32)
  if tb.text.len > 0:
    glColor4f(1, 1, 1, 1)
    var displayText = tb.text
    if displayText.len > 50:
      displayText = displayText[^50..^1]
    for c in displayText:
      glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  else:
    glColor4f(0.5, 0.5, 0.5, 1)
    for c in tb.placeholder:
      glutBitmapCharacter(GLUT_BITMAP_8_BY_13, c.int32)
  
  # Cursor
  if tb.focused and (getTime() * 2).int mod 2 == 0:
    let cursorX = x + 5 + tb.cursorPos * 8
    glBegin(GL_LINES)
    glColor4f(1, 1, 1, 1)
    glVertex2f(cursorX.float32, (y + 5).float32)
    glVertex2f(cursorX.float32, (y + h - 5).float32)
    glEnd()

# ==================== Input Handling for Web Search ====================

proc handleWebSearchInput*(game: Game, x, y: int, clicked: bool, key: char = '\0') =
  if not game.webSearchVisible or game.webSearch == nil:
    return
  
  let gui = game.webSearch
  
  # Handle tab clicks
  var tabX = 10
  for i, tab in gui.tabs:
    let tabWidth = 150
    let tabHeight = 30
    let tabY = 55
    
    if clicked and x >= tabX and x <= tabX + tabWidth and y >= tabY and y <= tabY + tabHeight:
      gui.currentTab = i
      gui.addressBar.text = tab.url
      return
    
    # Close button
    if i > 0 and clicked and x >= tabX + tabWidth - 20 and x <= tabX + tabWidth and 
       y >= tabY and y <= tabY + 20:
      gui.tabs.delete(i)
      if gui.currentTab >= gui.tabs.len:
        gui.currentTab = gui.tabs.len - 1
      return
    
    tabX += tabWidth + 5
  
  # New tab button
  if clicked and x >= tabX and x <= tabX + 30 and y >= 55 and y <= 85:
    gui.newTab("about:blank", "New Tab")
    return
  
  # Handle address bar
  if gui.addressBar != nil:
    let (ax, ay, aw, ah) = gui.addressBar.bounds
    if x >= ax and x <= ax + aw and y >= ay and y <= ay + ah:
      gui.addressBar.focused = true
      if clicked:
        # Handle text input (simplified)
        if key != '\0':
          if key == '\b':  # Backspace
            if gui.addressBar.cursorPos > 0:
              gui.addressBar.text = gui.addressBar.text[0..gui.addressBar.cursorPos-2] &
                                    gui.addressBar.text[gui.addressBar.cursorPos..^1]
              gui.addressBar.cursorPos -= 1
          elif key == '\r':  # Enter
            let text = gui.addressBar.text
            if text.startsWith("http://") or text.startsWith("https://") or text.contains("."):
              asyncCheck gui.navigateToTab(gui.currentTab, text)
            else:
              asyncCheck gui.navigateToTab(gui.currentTab, "search:" & text)
          elif key >= ' ' and key <= '~':  # Printable characters
            gui.addressBar.text.insert($key, gui.addressBar.cursorPos)
            gui.addressBar.cursorPos += 1
    else:
      gui.addressBar.focused = false
  
  # Handle navigation buttons
  handleButtonClick(gui.backButton, x, y, clicked)
  handleButtonClick(gui.forwardButton, x, y, clicked)
  handleButtonClick(gui.refreshButton, x, y, clicked)
  handleButtonClick(gui.searchButton, x, y, clicked)
  handleButtonClick(gui.bookmarkButton, x, y, clicked)
  
  # Handle search result clicks
  if gui.currentTab >= 0 and gui.currentTab < gui.tabs.len:
    let tab = gui.tabs[gui.currentTab]
    if clicked and tab.searchResults.len > 0:
      var yPos = 120
      for i, result in tab.searchResults:
        if y >= yPos - 10 and y <= yPos + 40:
          asyncCheck gui.navigateToTab(gui.currentTab, result.url)
          break
        yPos += 60

proc handleButtonClick*(btn: Button, x, y: int, clicked: bool) =
  let (bx, by, bw, bh) = btn.bounds
  if x >= bx and x <= bx + bw and y >= by and y <= by + bh:
    btn.state = if clicked: bsPressed else: bsHovered
    if clicked and btn.onClick != nil:
      btn.onClick()
  else:
    btn.state = bsNormal

# ==================== Update Game Initialization ====================

proc initGame*(playerName: string = "Player"): Game =
  new(result)
  
  # ... existing initialization code ...
  
  # Initialize web search
  result.webSearch = createWebSearchGui(result[])
  result.webSearchVisible = false
  result.httpClient = newAsyncHttpClient(userAgent=UserAgent)

# ==================== Update Key Callback ====================

proc keyCallback*(window: GLFWwindow, key, scancode, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  
  # ... existing key handling ...
  
  # Web search toggle (F2 key)
  elif key == GLFW_KEY_F2 and action == GLFW_PRESS:
    game.webSearchVisible = not game.webSearchVisible
    if game.webSearchVisible:
      game.mouseCaptured = false
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL)
    else:
      game.mouseCaptured = true
      glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED)
  
  # Handle web search input when visible
  if game.webSearchVisible and game.webSearch != nil:
    if action == GLFW_PRESS or action == GLFW_REPEAT:
      var char: char = '\0'
      # Convert key to char (simplified)
      if key >= GLFW_KEY_A and key <= GLFW_KEY_Z:
        if (mods and GLFW_MOD_SHIFT) != 0:
          char = char(ord('A') + (key - GLFW_KEY_A))
        else:
          char = char(ord('a') + (key - GLFW_KEY_A))
      elif key >= GLFW_KEY_0 and key <= GLFW_KEY_9:
        char = char(ord('0') + (key - GLFW_KEY_0))
      elif key == GLFW_KEY_SPACE:
        char = ' '
      elif key == GLFW_KEY_BACKSPACE:
        char = '\b'
      elif key == GLFW_KEY_ENTER:
        char = '\r'
      
      if char != '\0':
        handleWebSearchInput(game[], game.mouseX, game.mouseY, false, char)

# ==================== Update Mouse Callback ====================

proc mouseCallback*(window: GLFWwindow, xpos, ypos: float64) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  
  if game.webSearchVisible:
    game.mouseX = xpos.int
    game.mouseY = ypos.int
    handleWebSearchInput(game[], xpos.int, ypos.int, false)
    return
  
  # ... existing mouse handling ...

proc mouseButtonCallback*(window: GLFWwindow, button, action, mods: int32) {.cdecl.} =
  let game = cast[ptr Game](glfwGetWindowUserPointer(window))
  
  if game.webSearchVisible:
    handleWebSearchInput(game[], game.mouseX, game.mouseY, action == GLFW_PRESS)
    return
  
  # ... existing mouse button handling ...

# ==================== Update Render Function ====================

proc render*(game: Game) =
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  
  if game.webSearchVisible:
    # Render web search overlay
    renderWebSearch(game)
  else:
    # Render normal game
    renderWorld(game)
    
    if game.currentScreen != gsGame or game.chat.visible:
      renderGui(game)
    
    if game.currentScreen == gsGame:
      renderHotbar(game)
    
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

# ==================== Main ====================

proc main() =
  echo "Starting NimCraft with GUI, API, and Web Search..."
  
  let game = initGame("Player")
  
  # Start API server if enabled
  if game.apiEnabled:
    asyncCheck game.api.startApiServer(game.settings.apiPort)
  
  # Run the game
  game.run()

when isMainModule:
  main()