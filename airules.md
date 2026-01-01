When creating remotes events or remotes functions, don't use roblox remotes, use bytenet instead
When creating events for others script in the same context, use Signal library
When creating pcalls, etc use Promise

When using bytenet, don't use :listen or :send, the real usage is .listen and .send (to be sure look at the documentation : https://ffrostfall.github.io/ByteNet/api/functions/definePacket/)
When something i give you a path to something, don't try to do findfirstchild etc, use waitforchild on the main one and just take the rest directly in a variable
Every time i ask for the creation of a new system, go check if there are known libraries on roblox devforum etc that could help us
BillboardGUI can't have viewportframe directly in the workspace, you need to do it in PlayerGUI and set Adornee to the target part.
The fastest wait time is task.wait(0), it's often better that you use this instead of task.wait(0.1)