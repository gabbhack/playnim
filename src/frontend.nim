include karax / prelude
import karax / [vstyles, kdom]
import jsffi except `&`
import jsconsole

import macros, strutils

macro createAliases(tag: string, body: untyped): untyped =
  result = newStmtList()
  for classes in body:
    assert classes.kind == nnkStrLit, "Input must be a list of string literals"
    let tmplName = newIdentNode(classes.strVal.multiReplace([(" ", ""), ("-", "")]))
    result.add quote do:
      macro `tmplName`(rest: varargs[untyped]): untyped =
        var
          exprs: seq[NimNode]
          classes = `classes`
        for argument in rest:
          if $argument[0] != "class":
            exprs.add argument
          else:
            classes = classes & " " & argument[1].strVal

        var ret = nnkCall.newTree(
          newIdentNode("buildHtml"),
          nnkCall.newTree(
            newIdentNode(`tag`)
          )
        )
        for expr in exprs:
          ret[1].add expr
        ret[1].add nnkExprEqExpr.newTree(
            newIdentNode("class"),
            newLit(classes)
          )
        ret

createAliases("button"):
  "main button"

createAliases("tdiv"):
  "headerbar"
  "mainarea"
  "base column"
  "bar"
  "big editor"
  "optionsbar"
  "content2"

type
  CodeMirror = distinct Element
  Worker {.importc.} = ref object
  Message[T] {.importc.} = object
    data: T

proc newCodeMirror(element: Element, config: js): CodeMirror {. importcpp: "CodeMirror(@)" .}
proc getValue(cm: CodeMirror): kstring {.importcpp: "#.getValue()".}
proc setOption(cm: CodeMirror, key: kstring, value: js) {.importcpp: "#.setOption(@)".}
proc replaceSelection(cm: CodeMirror, value: kstring) {.importcpp: "#.replaceSelection(@)".}
proc refresh(cm: CodeMirror) {.importcpp: "#.refresh()".}
proc replace(text: kstring, this: kstring, to: kstring): kstring {.importcpp: "#.replace(@)".}
proc replace(text: kstring, this: kstring, to: kstring, to2: kstring): kstring {.importcpp: "#.replace(@)".}
proc newWorker(url: kstring): Worker {.importcpp: "new Worker(@)".}
proc onMessage[T](self: Worker, function: proc (msg: Message[T])) {.importcpp: "#.onmessage = @".}
proc postMessage[T](self: Worker, message: T) {.importcpp: "#.postMessage(@)".}
proc terminate(self: Worker) {.importcpp: "#.terminate()".}

const knownVersions = [
  "1.6.12".kstring,
  "1.4.8",
  "1.2.18",
  "1.0.8"
]

var
  outputText = "".kstring
  myCodeMirror: CodeMirror
  runningCode = false

proc onReceiveMessage(message: Message[kstring]) =
  console.log("Receive message from worker".kstring)
  console.log(message.data)
  outputText = message.data
  runningCode = false
  redraw(kxi)

var worker = newWorker("assets/" & knownVersions[0] & ".js")
worker.onMessage(onReceiveMessage)

proc runCode() =
  outputText = ""
  runningCode = true
  console.log("Send message to worker".kstring)
  worker.postMessage(myCodeMirror.getValue())
  redraw(kxi)

proc postRender(data: RouterData) =
  if myCodeMirror.Element == nil:
    myCodeMirror = newCodeMirror(kdom.getElementById("editor"), js{
      mode: "nim".kstring,
      value: "".kstring,
      tabSize: 2,
      lineNumbers: true,
      theme: "dracula".kstring
    })
    myCodeMirror.setOption("extraKeys", js{
      Tab: proc(cm: CodeMirror) =
        cm.replaceSelection("  ")
      ,
      "Ctrl-Enter".kstring: proc(cm: CodeMirror) =
        if (not runningCode): runCode()
      ,
      "Cmd-Enter".kstring: proc(cm: CodeMirror) =
        if (not runningCode): runCode()
    })

proc changeNimVersion() =
  runningCode = false
  worker.terminate()
  worker = newWorker("assets/" & kdom.getElementById("nimversion").value & ".js")
  worker.onMessage(onReceiveMessage)

proc changeFontSize() =
  let
    editor = kdom.getElementById("editor")
    fontSizeInput = kdom.getElementById("fontsize")
  editor.applyStyle(style(fontSize, fontSizeInput.value & "px".kstring))
  myCodeMirror.refresh()

proc createDom(data: RouterData): VNode =
  result = buildHtml(tdiv):
    headerbar:
      a(href = "https://nimplay.gabb.eu.org"):
        img(src = "/assets/logo.svg")
        span: text "Playground".kstring
      a(href = "https://github.com/gabbhack/nimplay"):
        span: text "Code on GitHub".kstring
    mainarea:
      baseColumn:
        bigEditor(id = "editor", class = "monospace"):
          optionsBar:
            span:
              text "Font size: ".kstring
              input(`type` = "number", id = "fontsize", value = "13", `min` = "8", `max` = "50", step = "1", required = "required", onchange = changeFontSize)
            span:
              text " Nim version: ".kstring
              select(id = "nimversion", onchange = changeNimVersion):
                for version in knownVersions:
                  option:
                    text version
        bar:
          if not runningCode:
            mainButton(onclick = runCode):
              text "Run!"
              span(class = "buttonhint"):
                text "(ctrl-enter)".kstring
          else:
            mainButton(class = "is-loading"):
              text "Run!".kstring
        content2(id = "output"):
          pre(class = "monospace"):
            verbatim outputText

setRenderer createDom, "ROOT", postRender
setForeignNodeId "tour"
setForeignNodeId "editor"
