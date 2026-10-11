local Server = script.Parent

require(Server.PlayerData).init()
require(Server.Shop).init()
require(Server.Monetization).init()
require(Server.RaceManager).start()
