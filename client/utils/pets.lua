-- utils/pets.lua
-- Pixel War Online - Pet Definitions

local pets = {

BASE_STAT_CEILING = 800,
AUGMENT_STEP = 10,

GROWTH = {
    hp  = 0.053,
    atk = 0.036,
    def = 0.0367,
    spd = 0.039,
},

--------------------------------------------------
-- SMALL PETS
--------------------------------------------------
cat = {
    id = "cat",
    name = "Cat",
    size = "small",
    spriteSize = 32,
    homeSize = 64,
    baseTotal = 170,
    augmentLimit = 63,

    base = {
        hp  = 30,
        atk = 20,
        def = 40,
        spd = 80
    }
},

snake = {
    id = "snake",
    name = "Snake",
    size = "small",
    spriteSize = 48,
    homeSize = 96,
    baseTotal = 420,
    augmentLimit = 38,

    base = {
        hp  = 100,
        atk = 150,
        def = 70,
        spd = 100
    }
},

parrot = {
    id = "parrot",
    name = "Parrot",
    size = "small",
    spriteSize = 32,
    homeSize = 64,
    baseTotal = 360,
    augmentLimit = 44,

    base = {
        hp  = 100,
        atk = 80,
        def = 90,
        spd = 90
    }
},

wasp = {
    id = "wasp",
    name = "Wasp",
    size = "small",
    spriteSize = 48,
    homeSize = 96,
    baseTotal = 460,
    augmentLimit = 34,

    base = {
        hp  = 70,
        atk = 60,
        def = 80,
        spd = 250
    }
},

cheetah = {
    id = "cheetah",
    name = "Cheetah",
    size = "small",
    spriteSize = 48,
    homeSize = 96,
    baseTotal = 350,
    augmentLimit = 45,

    base = {
        hp  = 80,
        atk = 80,
        def = 80,
        spd = 110
    }
},

panda = {
    id = "panda",
    name = "Panda",
    size = "small",
    spriteSize = 56,
    homeSize = 112,
    baseTotal = 310,
    augmentLimit = 49,

    base = {
        hp  = 120,
        atk = 80,
        def = 50,
        spd = 60
    }
},

--------------------------------------------------
-- MEDIUM PETS
--------------------------------------------------
dog = {
    id = "dog",
    name = "Dog",
    size = "medium",
    spriteSize = 48,
    homeSize = 96,
    baseTotal = 210,
    augmentLimit = 59,

    base = {
        hp  = 50,
        atk = 40,
        def = 60,
        spd = 60
    }
},

capybara = {
    id = "capybara",
    name = "Capybara",
    size = "medium",
    spriteSize = 48,
    homeSize = 96,
    baseTotal = 340,
    augmentLimit = 46,

    base = {
        hp  = 80,
        atk = 100,
        def = 60,
        spd = 100
    }
},

raccoon = {
    id = "raccoon",
    name = "Raccoon",
    size = "medium",
    spriteSize = 32,
    homeSize = 48,
    baseTotal = 380,
    augmentLimit = 42,

    base = {
        hp  = 90,
        atk = 120,
        def = 70,
        spd = 100
    }
},

--------------------------------------------------
-- LARGE PETS
--------------------------------------------------
horse = {
    id = "horse",
    name = "Horse",
    size = "large",
    homeSize = 56,
    spriteSize = 112,
    baseTotal = 350,
    augmentLimit = 45,

    base = {
        hp  = 100,
        atk = 100,
        def = 90,
        spd = 60
    }
},

hippo = {
    id = "hippo",
    name = "Hippo",
    size = "large",
    spriteSize = 64,
    homeSize = 128,
    baseTotal = 420,
    augmentLimit = 38,

    base = {
        hp  = 120,
        atk = 200,
        def = 100,
        spd = 100
    }
},

turtle = {
    id = "turtle",
    name = "Turtle",
    size = "large",
    spriteSize = 48,
    homeSize = 96,
    baseTotal = 380,
    augmentLimit = 42,

    base = {
        hp  = 120,
        atk = 120,
        def = 70,
        spd = 70
    }
},

rhino = {
    id = "rhino",
    name = "Rhino",
    size = "large",
    spriteFolder = "Rhino",
    spriteSize = 64,
    homeSize = 128,
    baseTotal = 490,
    augmentLimit = 31,

    base = {
        hp  = 150,
        atk = 150,
        def = 90,
        spd = 100
    }
},

guar = {
    id = "guar",
    name = "Guar",
    size = "large",
    spriteFolder = "Guar",
    spriteSize = 64,
    homeSize = 128,
    baseTotal = 530,
    augmentLimit = 27,

    base = {
        hp  = 200,
        atk = 200,
        def = 70,
        spd = 60
    }
},

alligator = {
    id = "alligator",
    name = "Alligator",
    size = "large",
    spriteSize = 56,
    homeSize = 112,
    baseTotal = 640,
    augmentLimit = 16,

    base = {
        hp  = 250,
        atk = 250,
        def = 70,
        spd = 70
    }
},

polar_bear = {
    id = "polar_bear",
    name = "Polar Bear",
    size = "large",
    spriteFolder = "Polar bear",
    spriteSize = 64,
    homeSize = 128,
    baseTotal = 570,
    augmentLimit = 23,

    base = {
        hp  = 120,
        atk = 150,
        def = 100,
        spd = 200
    }
},

elephant = {
    id = "elephant",
    name = "Elephant",
    size = "large",
    spriteFolder = "Elephant",
    spriteSize = 72,
    homeSize = 144,
    baseTotal = 640,
    augmentLimit = 16,

    base = {
        hp  = 200,
        atk = 200,
        def = 120,
        spd = 120
    }
},

tiger = {
    id = "tiger",
    name = "Tiger",
    size = "large",
    spriteFolder = "Tiger",
    spriteSize = 64,
    homeSize = 128,
    baseTotal = 500,
    augmentLimit = 30,

    base = {
        hp  = 100,
        atk = 150,
        def = 100,
        spd = 150
    }
}

}

function pets.calculateStats(petId, avatarStats, augments)
    local pet = pets[petId]
    if not pet then return nil end

    avatarStats = avatarStats or {}
    augments = augments or {}

    return {
        hp = math.floor((avatarStats.hp or 100) * ((pet.base.hp or 0) + (augments.hp or 0) * pets.AUGMENT_STEP) / 100),
        atk = math.floor((avatarStats.attack or avatarStats.atk or 100) * ((pet.base.atk or 0) + (augments.atk or 0) * pets.AUGMENT_STEP) / 100),
        def = math.floor((avatarStats.defense or avatarStats.def or 100) * ((pet.base.def or 0) + (augments.def or 0) * pets.AUGMENT_STEP) / 100),
        spd = math.floor((avatarStats.speed or avatarStats.spd or 100) * ((pet.base.spd or 0) + (augments.spd or 0) * pets.AUGMENT_STEP) / 100),
    }
end

return pets
