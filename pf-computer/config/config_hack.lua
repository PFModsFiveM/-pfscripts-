Config = Config or {}

Config.Hacking = {
    Enabled = true,

    Tools = {
        basic = {
            item = 'hack_usb_basic',
            label = 'Basic USB Cracker',
            stages = 2,
            difficulty = 'easy',
            minigames = { 'hack_keypad_bruteforce' }
        },
        advanced = {
            item = 'hack_usb_advanced',
            label = 'Advanced USB Cracker',
            stages = 3,
            difficulty = 'medium',
            minigames = { 'hack_keypad_bruteforce', 'hack_dot_matrix', 'hack_voltage_nodes' }
        },
        master = {
            item = 'hack_usb_master',
            label = 'Master Quantum Key',
            stages = 4,
            difficulty = 'hard',
            minigames = { 'hack_fingerprint_clone', 'hack_keypad_bruteforce', 'hack_voltage_nodes', 'hack_dot_matrix' }
        }
    },

    Difficulty = {
        easy = {
            codeLength = 4,
            memoryDigits = 4,
            mathMax = 20,
            typingLength = 6,
            timeLimitMs = 18000
        },
        medium = {
            codeLength = 5,
            memoryDigits = 6,
            mathMax = 50,
            typingLength = 8,
            timeLimitMs = 12000
        },
        hard = {
            codeLength = 6,
            memoryDigits = 8,
            mathMax = 100,
            typingLength = 10,
            timeLimitMs = 8000
        }
    }
}
