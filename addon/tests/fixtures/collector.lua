ForeverDiffCollectorDB = {
	["build"] = {
		["build"] = "70001",
		["interface"] = 16001,
		["version"] = "1.60.1",
	},
	["entrances"] = {
		[36] = {
			["exit"] = true,
			["map"] = 1436,
			["samples"] = 2,
			["x"] = 0.425,
			["y"] = 0.712,
		},
	},
	["items"] = {
		[45] = "Rat Tail",
		[85] = "Tough Jerky",
		[182] = "Large Candle",
		[647] = "Destiny",
	},
	["kills"] = {
		["Creature:6"] = 6,
		["GameObject:31"] = 5,
	},
	["loot"] = {
		["Creature:6"] = {
			[182] = 3,
		},
		["GameObject:31"] = {
			[647] = 1,
		},
	},
	["npcs"] = {
		[6] = {
			["classification"] = "normal",
			["factionGroup"] = "Neutral",
			["level"] = 2,
			["name"] = "Kobold Vermin",
			["reaction"] = 2,
			["sightings"] = {
				{
					["map"] = 1429,
					["x"] = 0.421,
					["y"] = 0.604,
				}, -- [1]
				{
					["map"] = 1429,
					["x"] = 0.446,
					["y"] = 0.589,
				}, -- [2]
			},
			["type"] = "Humanoid",
		},
		[12696] = {
			["classification"] = "rare",
			["factionGroup"] = "Horde",
			["level"] = 35,
			["name"] = "Senani Thunderheart",
			["reaction"] = 6,
			["sightings"] = {
				{
					["map"] = 1440,
					["x"] = 0.737,
					["y"] = 0.616,
				}, -- [1]
			},
			["type"] = "Humanoid",
		},
	},
	["objects"] = {
		["Splintertree Supply Crate"] = {
			["sightings"] = {
				{
					["map"] = 1440,
					["x"] = 0.731,
					["y"] = 0.609,
				}, -- [1]
			},
		},
	},
	["quests"] = {
		[2] = {
			["completion"] = "Sharptalon is dead, and the Silverwing Sentinels are one enemy lighter.",
			["description"] = "The mighty hippogryph Sharptalon has been slain, and his claw taken as a trophy of the hunt.",
			["ender"] = {
				["id"] = 12696,
				["type"] = "Creature",
			},
			["enderName"] = "Senani Thunderheart",
			["giver"] = {
				["id"] = 12696,
				["type"] = "Creature",
			},
			["giverName"] = "Senani Thunderheart",
			["objectives"] = "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post.",
			["pos"] = {
				["map"] = 1440,
				["x"] = 0.737,
				["y"] = 0.616,
			},
			["progress"] = "Have you brought me the claw of Sharptalon?",
			["rewards"] = {
				["choices"] = {
					182, -- [1]
				},
				["items"] = {
					647, -- [1]
				},
				["money"] = 1200,
				["xp"] = 250,
			},
			["title"] = "Sharptalon's Claw",
		},
		[500] = {
			["description"] = "The militia needs thick leather, and the kobolds of Elwynn have hides to spare.",
			["giver"] = {
				["id"] = 823,
				["type"] = "Creature",
			},
			["giverName"] = "Innkeeper Farley",
			["objectives"] = "Bring 5 Large Candles to Innkeeper Farley.",
			["pos"] = {
				["map"] = 1429,
				["x"] = 0.437,
				["y"] = 0.658,
			},
			["rewards"] = {
				["choices"] = {
				},
				["items"] = {
					45, -- [1]
				},
				["money"] = 300,
				["xp"] = 80,
			},
			["title"] = "The Militia Needs Candles",
		},
	},
	["realm"] = "Nostalgia",
	["vendors"] = {
		[823] = {
			["items"] = {
				{
					["id"] = 85,
					["numAvailable"] = -1,
					["price"] = 25,
					["quantity"] = 1,
				}, -- [1]
			},
		},
	},
	["version"] = 1,
}
