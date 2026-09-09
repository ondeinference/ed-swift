# Ed for Swift

Ed is a private, on-device agent for Swift apps. Onde runs the language model;
Ed gives that model a safe way to ask your app to do things.

It runs on iPhone, iPad, Mac, Apple TV, Apple Vision Pro, and Apple Watch. Model
input, conversation history, and tool results stay on the device unless a tool
you write deliberately sends data elsewhere.

## The mental model

If you are new to agents, think of Ed as a loop:

1. Your app sends a message to the model.
2. The model either answers, or requests one of your registered tools.
3. Ed checks the tool's risk level.
4. Your Swift code runs the approved tool and returns text.
5. The model reads that result and writes the final answer.

The model cannot call arbitrary Swift APIs. It only sees tools your app
registers.

## Installation

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/ondeinference/onde-ed-swift
```

Then add the `Ed` product to your target and import it:

```swift
import Ed
```

## Quick start

First, describe a tool and implement it. A JSON schema tells the model which
arguments it may provide:

```swift
import Ed

struct BatteryTool: EdTool {
    let definition = EdToolDefinition.readOnly(
        name: "battery_level",
        description: "Read the device battery percentage",
        parametersSchema: #"{"type":"object","properties":{}}"#
    )

    func execute(arguments: String) async throws -> String {
        // Read the real value from your platform API here.
        "The battery is at 73 percent."
    }
}
```

Then create the agent, register the tool, and load the default model:

```swift
let ed = EdAgent { call in
    // This callback is used only for mutating tools.
    let userApproved = await showApproval(for: call)
    return userApproved ? .allowOnce : .deny
}

try await ed.register(BatteryTool())
try await ed.loadDefaultAgentModel(
    systemPrompt: "You are a concise assistant inside my app."
)

let reply = try await ed.run("How much battery do I have?")
print(reply.text)
```

Use `.readOnly` for tools that only inspect state. Use `.mutating` for tools
that save, send, purchase, delete, unlock, or otherwise change something. Ed
runs read-only tools automatically and sends every mutating call through your
approval callback.

Observe progress and tool activity with an async stream:

```swift
for await event in ed.events() {
    print(event)
}
```

Cancelling the Swift task also cancels the active Ed turn:

```swift
let task = Task { try await ed.run("Do the task") }
task.cancel()
```

See [`Examples/EdExample`](Examples/EdExample) for a complete SwiftUI example
with a read-only device tool and an approval-gated mutating tool.

## Local development

Keep `onde`, `onde-ed`, and `onde-ed-swift` next to one another, then build a
local framework before running Swift tests:

```sh
make macos
swift test
```

Use `make ios`, `make tvos`, `make visionos`, or `make watchos` for another
Apple platform. The package automatically uses `EdFramework.xcframework` when
that local file exists. Without it, SwiftPM downloads the signed release asset.

## Licence

Ed is available under either the MIT License or Apache License 2.0.
