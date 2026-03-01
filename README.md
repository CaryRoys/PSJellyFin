<center><img src="https://raw.githubusercontent.com/CaryRoys/PSJellyFin/refs/heads/main/PSJellyFin.png?raw=true" width="200" height="200" /></center>


# PSJellyFin
A Powershell JellyFin API module

Written largely by Claude Code, based on the API spec at https://api.jellyfin.org, and noodled on by the author on Medium:

https://medium.com/@caryroys/a-working-example-of-jellyfin-automation-196d72bf4542

https://medium.com/@caryroys/a-working-example-of-jellyfin-automation-ai-redux-2458b360837a

# Getting Started

It's a snap:

`Connect-JellyfinServer -ServerUrl http://myhost:port -Username user -Password password`

or

`Connect-JellyfinServer -ServerUrl http://myhost:port -ApiKey myapikey`

Your session credentials are cached, and you can start calling API's.
