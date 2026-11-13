ZUK_TRACE_FLOW = false
ZUK_TRACE_TABLES = false
local function main(...)
	local cliArgs = { ... }
	if #cliArgs == 0 and type(arg) == "table" then
		for i = 1, #arg do
			cliArgs[i] = arg[i]
		end
	end
	local cliMode = #cliArgs > 0
	local ZukDecompile
	local function initialize()
		local FLOAT_PRECISION = 7
		local Reader = {}
		function Reader.new(bytecode)
			local stream = buffer.fromstring(bytecode)
			local cursor = 0
			local blen = buffer.len(stream)
			local self = {}
			local markTrail = {}
			local MARK_TRAIL_MAX = 40
			function self:mark(label)
				markTrail[#markTrail + 1] = label .. " @" .. cursor
				if #markTrail > MARK_TRAIL_MAX then
					table.remove(markTrail, 1)
				end
			end
			local function guard(n)
				if cursor + n > blen then
					error(
						string.format(
							"Uh oh! OOB: it needs %d byte(s) at offset %d (buf len %d)  maybe an opcode issue? trail: %s",
							n,
							cursor,
							blen,
							table.concat(markTrail, " -> ")
						),
						2
					)
				end
			end
			function self:len()
				return blen
			end
			function self:nextByte()
				guard(1)
				local r = buffer.readu8(stream, cursor)
				cursor += 1
				return r
			end
			function self:nextSignedByte()
				guard(1)
				local r = buffer.readi8(stream, cursor)
				cursor += 1
				return r
			end
			function self:nextBytes(count)
				local t = {}
				for i = 1, count do
					t[i] = self:nextByte()
				end
				return t
			end
			function self:nextUInt32()
				guard(4)
				local r = buffer.readu32(stream, cursor)
				cursor += 4
				return r
			end
			function self:nextInt32()
				guard(4)
				local r = buffer.readi32(stream, cursor)
				cursor += 4
				return r
			end
			function self:nextFloat()
				guard(4)
				local r = buffer.readf32(stream, cursor)
				cursor += 4
				return tonumber(string.format("%0." .. FLOAT_PRECISION .. "f", r))
			end
			function self:nextVarInt()
				local result = 0
				for i = 0, 4 do
					local b = self:nextByte()
					result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), i * 7))
					if not bit32.btest(b, 0x80) then
						break
					end
				end
				return result
			end
			function self:pos()
				return cursor
			end
			function self:seek(n)
				cursor = n
			end
			function self:nextVarInt64()
				local result, mult = 0, 1
				for _ = 1, 10 do
					local b = self:nextByte()
					result += bit32.band(b, 0x7F) * mult
					if not bit32.btest(b, 0x80) then
						break
					end
					mult *= 128
				end
				return result
			end
			function self:nextString(slen)
				slen = slen or self:nextVarInt()
				if slen == 0 then
					return ""
				end
				guard(slen)
				local r = buffer.readstring(stream, cursor, slen)
				cursor += slen
				return r
			end
			function self:nextDouble()
				guard(8)
				local r = buffer.readf64(stream, cursor)
				cursor += 8
				return r
			end
			return self
		end
		function Reader:Set(fp)
			FLOAT_PRECISION = fp
		end
		local Strings = {
			SUCCESS = "%s",
			TIMEOUT = "-- DECOMPILER TIMEOUT",
			COMPILATION_FAILURE = "-- SCRIPT FAILED TO COMPILE, ERROR:\n%s",
			UNSUPPORTED_LBC_VERSION = "-- BYTECODE VERSION %d IS NOT SUPPORTED (EXPECTED %d-%d)",
			USED_GLOBALS = "-- USED GLOBALS: %s.\n",
			DECOMPILER_REMARK = "-- DECOMPILER REMARK: %s\n",
		}
		local CASE_MULTIPLIER = 227
		local Luau = {
			OpCode = {
				{ name = "NOP", type = "none" },
				{ name = "BREAK", type = "none" },
				{ name = "LOADNIL", type = "A" },
				{ name = "LOADB", type = "ABC" },
				{ name = "LOADN", type = "AsD" },
				{ name = "LOADK", type = "AD" },
				{ name = "MOVE", type = "AB" },
				{ name = "GETGLOBAL", type = "AC", aux = true },
				{ name = "SETGLOBAL", type = "AC", aux = true },
				{ name = "GETUPVAL", type = "AB" },
				{ name = "SETUPVAL", type = "AB" },
				{ name = "CLOSEUPVALS", type = "A" },
				{ name = "GETIMPORT", type = "AD", aux = true },
				{ name = "GETTABLE", type = "ABC" },
				{ name = "SETTABLE", type = "ABC" },
				{ name = "GETTABLEKS", type = "ABC", aux = true },
				{ name = "SETTABLEKS", type = "ABC", aux = true },
				{ name = "GETTABLEN", type = "ABC" },
				{ name = "SETTABLEN", type = "ABC" },
				{ name = "NEWCLOSURE", type = "AD" },
				{ name = "NAMECALL", type = "ABC", aux = true },
				{ name = "CALL", type = "ABC" },
				{ name = "RETURN", type = "AB" },
				{ name = "JUMP", type = "sD" },
				{ name = "JUMPBACK", type = "sD" },
				{ name = "JUMPIF", type = "AsD" },
				{ name = "JUMPIFNOT", type = "AsD" },
				{ name = "JUMPIFEQ", type = "AsD", aux = true },
				{ name = "JUMPIFLE", type = "AsD", aux = true },
				{ name = "JUMPIFLT", type = "AsD", aux = true },
				{ name = "JUMPIFNOTEQ", type = "AsD", aux = true },
				{ name = "JUMPIFNOTLE", type = "AsD", aux = true },
				{ name = "JUMPIFNOTLT", type = "AsD", aux = true },
				{ name = "ADD", type = "ABC" },
				{ name = "SUB", type = "ABC" },
				{ name = "MUL", type = "ABC" },
				{ name = "DIV", type = "ABC" },
				{ name = "MOD", type = "ABC" },
				{ name = "POW", type = "ABC" },
				{ name = "ADDK", type = "ABC" },
				{ name = "SUBK", type = "ABC" },
				{ name = "MULK", type = "ABC" },
				{ name = "DIVK", type = "ABC" },
				{ name = "MODK", type = "ABC" },
				{ name = "POWK", type = "ABC" },
				{ name = "AND", type = "ABC" },
				{ name = "OR", type = "ABC" },
				{ name = "ANDK", type = "ABC" },
				{ name = "ORK", type = "ABC" },
				{ name = "CONCAT", type = "ABC" },
				{ name = "NOT", type = "AB" },
				{ name = "MINUS", type = "AB" },
				{ name = "LENGTH", type = "AB" },
				{ name = "NEWTABLE", type = "AB", aux = true },
				{ name = "DUPTABLE", type = "AD" },
				{ name = "SETLIST", type = "ABC", aux = true },
				{ name = "FORNPREP", type = "AsD" },
				{ name = "FORNLOOP", type = "AsD" },
				{ name = "FORGLOOP", type = "AsD", aux = true },
				{ name = "FORGPREP_INEXT", type = "A" },
				{ name = "FASTCALL3", type = "ABC", aux = true },
				{ name = "FORGPREP_NEXT", type = "A" },
				{ name = "NATIVECALL", type = "none" },
				{ name = "GETVARARGS", type = "AB" },
				{ name = "DUPCLOSURE", type = "AD" },
				{ name = "PREPVARARGS", type = "A" },
				{ name = "LOADKX", type = "A", aux = true },
				{ name = "JUMPX", type = "E" },
				{ name = "FASTCALL", type = "AC" },
				{ name = "COVERAGE", type = "E" },
				{ name = "CAPTURE", type = "AB" },
				{ name = "SUBRK", type = "ABC" },
				{ name = "DIVRK", type = "ABC" },
				{ name = "FASTCALL1", type = "ABC" },
				{ name = "FASTCALL2", type = "ABC", aux = true },
				{ name = "FASTCALL2K", type = "ABC", aux = true },
				{ name = "FORGPREP", type = "AsD" },
				{ name = "JUMPXEQKNIL", type = "AsD", aux = true },
				{ name = "JUMPXEQKB", type = "AsD", aux = true },
				{ name = "JUMPXEQKN", type = "AsD", aux = true },
				{ name = "JUMPXEQKS", type = "AsD", aux = true },
				{ name = "IDIV", type = "ABC" },
				{ name = "IDIVK", type = "ABC" },
				{ name = "GETUDATAKS", type = "ABC", aux = true },
				{ name = "SETUDATAKS", type = "ABC", aux = true },
				{ name = "NAMECALLUDATA", type = "ABC", aux = true },
				{ name = "NEWCLASSMEMBER", type = "ABC", aux = true },
				{ name = "CALLFB", type = "ABC", aux = true },
				{ name = "CMPPROTO", type = "AsD", aux = true },
				{ name = "FASTPCALL", type = "ABC" },
				{ name = "NEWCLASS", type = "ABC", aux = true },
				{ name = "_COUNT", type = "none" },
			},
			BytecodeTag = {
				LBC_VERSION_MIN = 3,
				LBC_VERSION_MAX = 14,
				LBC_TYPE_VERSION_MIN = 1,
				LBC_TYPE_VERSION_MAX = 3,
				LBC_CONSTANT_NIL = 0,
				LBC_CONSTANT_BOOLEAN = 1,
				LBC_CONSTANT_NUMBER = 2,
				LBC_CONSTANT_STRING = 3,
				LBC_CONSTANT_IMPORT = 4,
				LBC_CONSTANT_TABLE = 5,
				LBC_CONSTANT_CLOSURE = 6,
				LBC_CONSTANT_VECTOR = 7,
				LBC_CONSTANT_TABLE_WITH_CONSTANTS = 8,
				LBC_CONSTANT_INTEGER = 9,
				LBC_CONSTANT_CLASS_SHAPE = 10,
				LBC_CONSTANT_VECTORD = 11,
			},
			BytecodeType = {
				LBC_TYPE_NIL = 0,
				LBC_TYPE_BOOLEAN = 1,
				LBC_TYPE_NUMBER = 2,
				LBC_TYPE_STRING = 3,
				LBC_TYPE_TABLE = 4,
				LBC_TYPE_FUNCTION = 5,
				LBC_TYPE_THREAD = 6,
				LBC_TYPE_USERDATA = 7,
				LBC_TYPE_VECTOR = 8,
				LBC_TYPE_BUFFER = 9,
				LBC_TYPE_INTEGER = 10,
				LBC_TYPE_ANY = 15,
				LBC_TYPE_TAGGED_USERDATA_BASE = 64,
				LBC_TYPE_TAGGED_USERDATA_END = 64 + 32,
				LBC_TYPE_OPTIONAL_BIT = bit32.lshift(1, 7),
				LBC_TYPE_INVALID = 256,
			},
			CaptureType = { LCT_VAL = 0, LCT_REF = 1, LCT_UPVAL = 2 },
			BuiltinFunction = {
				LBF_NONE = 0,
				LBF_ASSERT = 1,
				LBF_MATH_ABS = 2,
				LBF_MATH_ACOS = 3,
				LBF_MATH_ASIN = 4,
				LBF_MATH_ATAN2 = 5,
				LBF_MATH_ATAN = 6,
				LBF_MATH_CEIL = 7,
				LBF_MATH_COSH = 8,
				LBF_MATH_COS = 9,
				LBF_MATH_DEG = 10,
				LBF_MATH_EXP = 11,
				LBF_MATH_FLOOR = 12,
				LBF_MATH_FMOD = 13,
				LBF_MATH_FREXP = 14,
				LBF_MATH_LDEXP = 15,
				LBF_MATH_LOG10 = 16,
				LBF_MATH_LOG = 17,
				LBF_MATH_MAX = 18,
				LBF_MATH_MIN = 19,
				LBF_MATH_MODF = 20,
				LBF_MATH_POW = 21,
				LBF_MATH_RAD = 22,
				LBF_MATH_SINH = 23,
				LBF_MATH_SIN = 24,
				LBF_MATH_SQRT = 25,
				LBF_MATH_TANH = 26,
				LBF_MATH_TAN = 27,
				LBF_BIT32_ARSHIFT = 28,
				LBF_BIT32_BAND = 29,
				LBF_BIT32_BNOT = 30,
				LBF_BIT32_BOR = 31,
				LBF_BIT32_BXOR = 32,
				LBF_BIT32_BTEST = 33,
				LBF_BIT32_EXTRACT = 34,
				LBF_BIT32_LROTATE = 35,
				LBF_BIT32_LSHIFT = 36,
				LBF_BIT32_REPLACE = 37,
				LBF_BIT32_RROTATE = 38,
				LBF_BIT32_RSHIFT = 39,
				LBF_TYPE = 40,
				LBF_STRING_BYTE = 41,
				LBF_STRING_CHAR = 42,
				LBF_STRING_LEN = 43,
				LBF_TYPEOF = 44,
				LBF_STRING_SUB = 45,
				LBF_MATH_CLAMP = 46,
				LBF_MATH_SIGN = 47,
				LBF_MATH_ROUND = 48,
				LBF_RAWSET = 49,
				LBF_RAWGET = 50,
				LBF_RAWEQUAL = 51,
				LBF_TABLE_INSERT = 52,
				LBF_TABLE_UNPACK = 53,
				LBF_VECTOR = 54,
				LBF_BIT32_COUNTLZ = 55,
				LBF_BIT32_COUNTRZ = 56,
				LBF_SELECT_VARARG = 57,
				LBF_RAWLEN = 58,
				LBF_BIT32_EXTRACTK = 59,
				LBF_GETMETATABLE = 60,
				LBF_SETMETATABLE = 61,
				LBF_TONUMBER = 62,
				LBF_TOSTRING = 63,
				LBF_BIT32_BYTESWAP = 64,
				LBF_BUFFER_READI8 = 65,
				LBF_BUFFER_READU8 = 66,
				LBF_BUFFER_WRITEU8 = 67,
				LBF_BUFFER_READI16 = 68,
				LBF_BUFFER_READU16 = 69,
				LBF_BUFFER_WRITEU16 = 70,
				LBF_BUFFER_READI32 = 71,
				LBF_BUFFER_READU32 = 72,
				LBF_BUFFER_WRITEU32 = 73,
				LBF_BUFFER_READF32 = 74,
				LBF_BUFFER_WRITEF32 = 75,
				LBF_BUFFER_READF64 = 76,
				LBF_BUFFER_WRITEF64 = 77,
				LBF_VECTOR_MAGNITUDE = 78,
				LBF_VECTOR_NORMALIZE = 79,
				LBF_VECTOR_CROSS = 80,
				LBF_VECTOR_DOT = 81,
				LBF_VECTOR_FLOOR = 82,
				LBF_VECTOR_CEIL = 83,
				LBF_VECTOR_ABS = 84,
				LBF_VECTOR_SIGN = 85,
				LBF_VECTOR_CLAMP = 86,
				LBF_VECTOR_MIN = 87,
				LBF_VECTOR_MAX = 88,
				LBF_MATH_LERP = 89,
				LBF_VECTOR_LERP = 90,
				LBF_MATH_ISNAN = 91,
				LBF_MATH_ISINF = 92,
				LBF_MATH_ISFINITE = 93,
				LBF_INTEGER_CREATE = 94,
				LBF_INTEGER_TONUMBER = 95,
				LBF_INTEGER_NEG = 96,
				LBF_INTEGER_ADD = 97,
				LBF_INTEGER_SUB = 98,
				LBF_INTEGER_MUL = 99,
				LBF_INTEGER_DIV = 100,
				LBF_INTEGER_MIN = 101,
				LBF_INTEGER_MAX = 102,
				LBF_INTEGER_REM = 103,
				LBF_INTEGER_IDIV = 104,
				LBF_INTEGER_UDIV = 105,
				LBF_INTEGER_UREM = 106,
				LBF_INTEGER_MOD = 107,
				LBF_INTEGER_CLAMP = 108,
				LBF_INTEGER_BAND = 109,
				LBF_INTEGER_BOR = 110,
				LBF_INTEGER_BNOT = 111,
				LBF_INTEGER_BXOR = 112,
				LBF_INTEGER_LT = 113,
				LBF_INTEGER_LE = 114,
				LBF_INTEGER_ULT = 115,
				LBF_INTEGER_ULE = 116,
				LBF_INTEGER_GT = 117,
				LBF_INTEGER_GE = 118,
				LBF_INTEGER_UGT = 119,
				LBF_INTEGER_UGE = 120,
				LBF_INTEGER_LSHIFT = 121,
				LBF_INTEGER_RSHIFT = 122,
				LBF_INTEGER_ARSHIFT = 123,
				LBF_INTEGER_LROTATE = 124,
				LBF_INTEGER_RROTATE = 125,
				LBF_INTEGER_EXTRACT = 126,
				LBF_INTEGER_BTEST = 127,
				LBF_INTEGER_COUNTRZ = 128,
				LBF_INTEGER_COUNTLZ = 129,
				LBF_INTEGER_BSWAP = 130,
				LBF_BUFFER_READINTEGER = 131,
				LBF_BUFFER_WRITEINTEGER = 132,
			},
			ProtoFlag = {
				LPF_NATIVE_MODULE = bit32.lshift(1, 0),
				LPF_NATIVE_COLD = bit32.lshift(1, 1),
				LPF_NATIVE_FUNCTION = bit32.lshift(1, 2),
			},
		}
		function Luau:INSN_OP(i)
			return bit32.band(i, 0xFF)
		end
		function Luau:INSN_A(i)
			return bit32.band(bit32.rshift(i, 8), 0xFF)
		end
		function Luau:INSN_B(i)
			return bit32.band(bit32.rshift(i, 16), 0xFF)
		end
		function Luau:INSN_C(i)
			return bit32.band(bit32.rshift(i, 24), 0xFF)
		end
		function Luau:INSN_D(i)
			return bit32.rshift(i, 16)
		end
		function Luau:INSN_sD(i)
			local D = self:INSN_D(i)
			return (D > 0x7FFF and D <= 0xFFFF) and (-(0xFFFF - D) - 1) or D
		end
		function Luau:INSN_E(i)
			return bit32.rshift(i, 8)
		end
		function Luau:GetBaseTypeString(t, checkOpt)
			local BT = self.BytecodeType
			local tag = bit32.band(t, bit32.bnot(BT.LBC_TYPE_OPTIONAL_BIT))
			local names = {
				[BT.LBC_TYPE_NIL] = "nil",
				[BT.LBC_TYPE_BOOLEAN] = "boolean",
				[BT.LBC_TYPE_NUMBER] = "number",
				[BT.LBC_TYPE_STRING] = "string",
				[BT.LBC_TYPE_TABLE] = "table",
				[BT.LBC_TYPE_FUNCTION] = "function",
				[BT.LBC_TYPE_THREAD] = "thread",
				[BT.LBC_TYPE_USERDATA] = "userdata",
				[BT.LBC_TYPE_VECTOR] = "Vector3",
				[BT.LBC_TYPE_BUFFER] = "buffer",
				[BT.LBC_TYPE_ANY] = "any",
			}
			local r = names[tag] or "unknown"
			if checkOpt then
				r ..= (bit32.band(t, BT.LBC_TYPE_OPTIONAL_BIT) == 0) and "" or "?"
			end
			return r
		end
		function Luau:GetBuiltinInfo(bfid)
			local BF = self.BuiltinFunction
			local map = {
				[BF.LBF_NONE] = "none",
				[BF.LBF_ASSERT] = "assert",
				[BF.LBF_TYPE] = "type",
				[BF.LBF_TYPEOF] = "typeof",
				[BF.LBF_RAWSET] = "rawset",
				[BF.LBF_RAWGET] = "rawget",
				[BF.LBF_RAWEQUAL] = "rawequal",
				[BF.LBF_RAWLEN] = "rawlen",
				[BF.LBF_TABLE_UNPACK] = "unpack",
				[BF.LBF_SELECT_VARARG] = "select",
				[BF.LBF_GETMETATABLE] = "getmetatable",
				[BF.LBF_SETMETATABLE] = "setmetatable",
				[BF.LBF_TONUMBER] = "tonumber",
				[BF.LBF_TOSTRING] = "tostring",
				[BF.LBF_MATH_ABS] = "math.abs",
				[BF.LBF_MATH_ACOS] = "math.acos",
				[BF.LBF_MATH_ASIN] = "math.asin",
				[BF.LBF_MATH_ATAN2] = "math.atan2",
				[BF.LBF_MATH_ATAN] = "math.atan",
				[BF.LBF_MATH_CEIL] = "math.ceil",
				[BF.LBF_MATH_COSH] = "math.cosh",
				[BF.LBF_MATH_COS] = "math.cos",
				[BF.LBF_MATH_DEG] = "math.deg",
				[BF.LBF_MATH_EXP] = "math.exp",
				[BF.LBF_MATH_FLOOR] = "math.floor",
				[BF.LBF_MATH_FMOD] = "math.fmod",
				[BF.LBF_MATH_FREXP] = "math.frexp",
				[BF.LBF_MATH_LDEXP] = "math.ldexp",
				[BF.LBF_MATH_LOG10] = "math.log10",
				[BF.LBF_MATH_LOG] = "math.log",
				[BF.LBF_MATH_MAX] = "math.max",
				[BF.LBF_MATH_MIN] = "math.min",
				[BF.LBF_MATH_MODF] = "math.modf",
				[BF.LBF_MATH_POW] = "math.pow",
				[BF.LBF_MATH_RAD] = "math.rad",
				[BF.LBF_MATH_SINH] = "math.sinh",
				[BF.LBF_MATH_SIN] = "math.sin",
				[BF.LBF_MATH_SQRT] = "math.sqrt",
				[BF.LBF_MATH_TANH] = "math.tanh",
				[BF.LBF_MATH_TAN] = "math.tan",
				[BF.LBF_MATH_CLAMP] = "math.clamp",
				[BF.LBF_MATH_SIGN] = "math.sign",
				[BF.LBF_MATH_ROUND] = "math.round",
				[BF.LBF_BIT32_ARSHIFT] = "bit32.arshift",
				[BF.LBF_BIT32_BAND] = "bit32.band",
				[BF.LBF_BIT32_BNOT] = "bit32.bnot",
				[BF.LBF_BIT32_BOR] = "bit32.bor",
				[BF.LBF_BIT32_BXOR] = "bit32.bxor",
				[BF.LBF_BIT32_BTEST] = "bit32.btest",
				[BF.LBF_BIT32_EXTRACT] = "bit32.extract",
				[BF.LBF_BIT32_EXTRACTK] = "bit32.extract",
				[BF.LBF_BIT32_LROTATE] = "bit32.lrotate",
				[BF.LBF_BIT32_LSHIFT] = "bit32.lshift",
				[BF.LBF_BIT32_REPLACE] = "bit32.replace",
				[BF.LBF_BIT32_RROTATE] = "bit32.rrotate",
				[BF.LBF_BIT32_RSHIFT] = "bit32.rshift",
				[BF.LBF_BIT32_COUNTLZ] = "bit32.countlz",
				[BF.LBF_BIT32_COUNTRZ] = "bit32.countrz",
				[BF.LBF_BIT32_BYTESWAP] = "bit32.byteswap",
				[BF.LBF_STRING_BYTE] = "string.byte",
				[BF.LBF_STRING_CHAR] = "string.char",
				[BF.LBF_STRING_LEN] = "string.len",
				[BF.LBF_STRING_SUB] = "string.sub",
				[BF.LBF_TABLE_INSERT] = "table.insert",
				[BF.LBF_VECTOR] = "Vector3.new",
				[BF.LBF_BUFFER_READI8] = "buffer.readi8",
				[BF.LBF_BUFFER_READU8] = "buffer.readu8",
				[BF.LBF_BUFFER_WRITEU8] = "buffer.writeu8",
				[BF.LBF_BUFFER_READI16] = "buffer.readi16",
				[BF.LBF_BUFFER_READU16] = "buffer.readu16",
				[BF.LBF_BUFFER_WRITEU16] = "buffer.writeu16",
				[BF.LBF_BUFFER_READI32] = "buffer.readi32",
				[BF.LBF_BUFFER_READU32] = "buffer.readu32",
				[BF.LBF_BUFFER_WRITEU32] = "buffer.writeu32",
				[BF.LBF_BUFFER_READF32] = "buffer.readf32",
				[BF.LBF_BUFFER_WRITEF32] = "buffer.writef32",
				[BF.LBF_BUFFER_READF64] = "buffer.readf64",
				[BF.LBF_BUFFER_WRITEF64] = "buffer.writef64",
				[BF.LBF_VECTOR_MAGNITUDE] = "vector.magnitude",
				[BF.LBF_VECTOR_NORMALIZE] = "vector.normalize",
				[BF.LBF_VECTOR_CROSS] = "vector.cross",
				[BF.LBF_VECTOR_DOT] = "vector.dot",
				[BF.LBF_VECTOR_FLOOR] = "vector.floor",
				[BF.LBF_VECTOR_CEIL] = "vector.ceil",
				[BF.LBF_VECTOR_ABS] = "vector.abs",
				[BF.LBF_VECTOR_SIGN] = "vector.sign",
				[BF.LBF_VECTOR_CLAMP] = "vector.clamp",
				[BF.LBF_VECTOR_MIN] = "vector.min",
				[BF.LBF_VECTOR_MAX] = "vector.max",
				[BF.LBF_MATH_LERP] = "math.lerp",
				[BF.LBF_VECTOR_LERP] = "vector.lerp",
				[BF.LBF_MATH_ISNAN] = "math.isnan",
				[BF.LBF_MATH_ISINF] = "math.isinf",
				[BF.LBF_MATH_ISFINITE] = "math.isfinite",
				[BF.LBF_INTEGER_CREATE] = "integer.create",
				[BF.LBF_INTEGER_TONUMBER] = "integer.tonumber",
				[BF.LBF_INTEGER_NEG] = "integer.neg",
				[BF.LBF_INTEGER_ADD] = "integer.add",
				[BF.LBF_INTEGER_SUB] = "integer.sub",
				[BF.LBF_INTEGER_MUL] = "integer.mul",
				[BF.LBF_INTEGER_DIV] = "integer.div",
				[BF.LBF_INTEGER_MIN] = "integer.min",
				[BF.LBF_INTEGER_MAX] = "integer.max",
				[BF.LBF_INTEGER_REM] = "integer.rem",
				[BF.LBF_INTEGER_IDIV] = "integer.idiv",
				[BF.LBF_INTEGER_UDIV] = "integer.udiv",
				[BF.LBF_INTEGER_UREM] = "integer.urem",
				[BF.LBF_INTEGER_MOD] = "integer.mod",
				[BF.LBF_INTEGER_CLAMP] = "integer.clamp",
				[BF.LBF_INTEGER_BAND] = "integer.band",
				[BF.LBF_INTEGER_BOR] = "integer.bor",
				[BF.LBF_INTEGER_BNOT] = "integer.bnot",
				[BF.LBF_INTEGER_BXOR] = "integer.bxor",
				[BF.LBF_INTEGER_LT] = "integer.lt",
				[BF.LBF_INTEGER_LE] = "integer.le",
				[BF.LBF_INTEGER_ULT] = "integer.ult",
				[BF.LBF_INTEGER_ULE] = "integer.ule",
				[BF.LBF_INTEGER_GT] = "integer.gt",
				[BF.LBF_INTEGER_GE] = "integer.ge",
				[BF.LBF_INTEGER_UGT] = "integer.ugt",
				[BF.LBF_INTEGER_UGE] = "integer.uge",
				[BF.LBF_INTEGER_LSHIFT] = "integer.lshift",
				[BF.LBF_INTEGER_RSHIFT] = "integer.rshift",
				[BF.LBF_INTEGER_ARSHIFT] = "integer.arshift",
				[BF.LBF_INTEGER_LROTATE] = "integer.lrotate",
				[BF.LBF_INTEGER_RROTATE] = "integer.rrotate",
				[BF.LBF_INTEGER_EXTRACT] = "integer.extract",
				[BF.LBF_INTEGER_BTEST] = "integer.btest",
				[BF.LBF_INTEGER_COUNTRZ] = "integer.countrz",
				[BF.LBF_INTEGER_COUNTLZ] = "integer.countlz",
				[BF.LBF_INTEGER_BSWAP] = "integer.bswap",
				[BF.LBF_BUFFER_READINTEGER] = "buffer.readinteger",
				[BF.LBF_BUFFER_WRITEINTEGER] = "buffer.writeinteger",
			}
			return map[bfid] or ("builtin#" .. tostring(bfid))
		end
		local LuauRawOpCode = Luau.OpCode
		local LuauRawOpcodeMap = {}
		local LuauEncodedOpCode
		do
			local encoded = {}
			for i, v in LuauRawOpCode do
				local rawOpcode = i - 1
				local case = bit32.band(rawOpcode * CASE_MULTIPLIER, 0xFF)
				LuauRawOpcodeMap[rawOpcode] = v
				encoded[case] = v
			end
			LuauEncodedOpCode = encoded
			Luau.OpCode = encoded
		end
		local LuauCompileUserdataInfo = true
		pcall(function()
			local ok, r = pcall(function()
				return game:GetFastFlag("LuauCompileUserdataInfo")
			end)
			if ok then
				LuauCompileUserdataInfo = r
			end
		end)
		local LuauBytecodeTag = Luau.BytecodeTag
		local LuauBytecodeType = Luau.BytecodeType
		local LuauCaptureType = Luau.CaptureType
		local LuauProtoFlag = Luau.ProtoFlag
		local function toBoolean(v)
			return v ~= 0
		end
		local function toEscapedString(v)
			if type(v) == "string" then
				return string.format("%q", v)
			end
			return tostring(v)
		end
		local function formatIndexString(key)
			if type(key) == "string" and key:match("^[%a_][%w_]*$") then
				return "." .. key
			end
			return "[" .. toEscapedString(key) .. "]"
		end
		local function padLeft(v, ch, n)
			local s = tostring(v)
			return string.rep(ch, math.max(0, n - #s)) .. s
		end
		local function padRight(v, ch, n)
			local s = tostring(v)
			return s .. string.rep(ch, math.max(0, n - #s))
		end
		local ROBLOX_GLOBALS = {
			game = true,
			workspace = true,
			script = true,
			plugin = true,
			settings = true,
			shared = true,
			UserSettings = true,
			print = true,
			warn = true,
			error = true,
			assert = true,
			pcall = true,
			xpcall = true,
			require = true,
			select = true,
			pairs = true,
			ipairs = true,
			next = true,
			unpack = true,
			type = true,
			typeof = true,
			tostring = true,
			tonumber = true,
			setmetatable = true,
			getmetatable = true,
			rawset = true,
			rawget = true,
			rawequal = true,
			rawlen = true,
			math = true,
			table = true,
			string = true,
			bit32 = true,
			coroutine = true,
			os = true,
			utf8 = true,
			task = true,
			buffer = true,
			Instance = true,
			Enum = true,
			Vector3 = true,
			Vector2 = true,
			CFrame = true,
			Color3 = true,
			BrickColor = true,
			UDim = true,
			UDim2 = true,
			Ray = true,
			Axes = true,
			Faces = true,
			NumberRange = true,
			NumberSequence = true,
			ColorSequence = true,
			TweenInfo = true,
			RaycastParams = true,
			OverlapParams = true,
			tick = true,
			time = true,
			wait = true,
			delay = true,
			spawn = true,
			_G = true,
			_VERSION = true,
		}
		local function isGlobal(key)
			return ROBLOX_GLOBALS[key] == true
		end
		local function Decompile(bytecode, options)
			local bytecodeVersion, typeEncodingVersion
			Reader:Set(7)
			local reader = Reader.new(bytecode)
			local function disassemble()
				reader:mark("header:typeVersion")
				if bytecodeVersion >= 4 then
					typeEncodingVersion = reader:nextByte()
				end
				local stringTable = {}
				local function readStringTable()
					reader:mark("stringtable:count")
					local n = reader:nextVarInt()
					for i = 1, n do
						reader:mark("stringtable[" .. i .. "/" .. n .. "]")
						stringTable[i] = reader:nextString()
					end
				end
				local userdataTypes = {}
				local function readUserdataTypes()
					while true do
						reader:mark("userdata:idx")
						local idx = reader:nextByte()
						if idx == 0 then
							break
						end
						reader:mark("userdata:type[" .. idx .. "]")
						userdataTypes[idx] = reader:nextVarInt()
					end
				end
				local protoTable = {}
				local function readProtoTable()
					reader:mark("prototable:count")
					local n = reader:nextVarInt()
					for i = 1, n do
						local protoId = i - 1
						local pfx = "proto[" .. protoId .. "/" .. n .. "]:"
						local proto = {
							id = protoId,
							instructions = {},
							constants = {},
							captures = {},
							innerProtos = {},
							instructionLineInfo = {},
						}
						protoTable[protoId] = proto
						local protoSize
						if bytecodeVersion >= 12 then
							reader:mark(pfx .. "protoSize")
							protoSize = reader:nextVarInt()
						end
						local protoStart = reader:pos()
						reader:mark(pfx .. "header")
						proto.maxStackSize = reader:nextByte()
						proto.numParams = reader:nextByte()
						proto.numUpvalues = reader:nextByte()
						proto.isVarArg = toBoolean(reader:nextByte())
						if bytecodeVersion >= 4 then
							reader:mark(pfx .. "flags")
							proto.flags = reader:nextByte()
							local resultTypedParams, resultTypedUpvalues, resultTypedLocals = {}, {}, {}
							reader:mark(pfx .. "typeinfo:size")
							local allTypeInfoSize = reader:nextVarInt()
							local hasTypeInfo = allTypeInfoSize > 0
							proto.hasTypeInfo = hasTypeInfo
							if hasTypeInfo then
								if typeEncodingVersion and typeEncodingVersion > 1 then
									reader:mark(pfx .. "typeinfo:skip(" .. allTypeInfoSize .. ")")
									for _ = 1, allTypeInfoSize do
										reader:nextByte()
									end
								else
									reader:mark(pfx .. "typeinfo:legacyblob(" .. allTypeInfoSize .. ")")
									local blob = reader:nextBytes(allTypeInfoSize)
									table.remove(blob, 1)
									table.remove(blob, 1)
									resultTypedParams = blob
								end
							end
							proto.typedParams = resultTypedParams
							proto.typedUpvalues = resultTypedUpvalues
							proto.typedLocals = resultTypedLocals
						end
						reader:mark(pfx .. "instructions:count")
						proto.sizeInstructions = reader:nextVarInt()
						reader:mark(pfx .. "instructions[0.." .. proto.sizeInstructions .. "]")
						for j = 1, proto.sizeInstructions do
							proto.instructions[j] = reader:nextUInt32()
						end
						reader:mark(pfx .. "constants:count")
						proto.sizeConstants = reader:nextVarInt()
						for j = 1, proto.sizeConstants do
							reader:mark(pfx .. "const[" .. (j - 1) .. "/" .. proto.sizeConstants .. "]:type")
							local constType = reader:nextByte()
							local constValue
							local BT = LuauBytecodeTag
							reader:mark(pfx .. "const[" .. (j - 1) .. "]:value(type=" .. constType .. ")")
							if constType == BT.LBC_CONSTANT_BOOLEAN then
								constValue = toBoolean(reader:nextByte())
							elseif constType == BT.LBC_CONSTANT_NUMBER then
								constValue = reader:nextDouble()
							elseif constType == BT.LBC_CONSTANT_STRING then
								constValue = stringTable[reader:nextVarInt()]
							elseif constType == BT.LBC_CONSTANT_IMPORT then
								local id = reader:nextUInt32()
								local idxCount = bit32.rshift(id, 30)
								local ci1 = bit32.band(bit32.rshift(id, 20), 0x3FF)
								local ci2 = bit32.band(bit32.rshift(id, 10), 0x3FF)
								local ci3 = bit32.band(id, 0x3FF)
								local tag = ""
								local function kv(idx)
									return proto.constants[idx + 1]
								end
								local function kstr(idx)
									return tostring(kv(idx) and kv(idx).value or "")
								end
								local ROBLOX_SERVICES = {
									Players = true,
									ReplicatedStorage = true,
									ReplicatedFirst = true,
									ServerStorage = true,
									ServerScriptService = true,
									StarterGui = true,
									StarterPack = true,
									StarterPlayer = true,
									Workspace = true,
									Lighting = true,
									SoundService = true,
									RunService = true,
									UserInputService = true,
									TweenService = true,
									HttpService = true,
									MarketplaceService = true,
									DataStoreService = true,
									MessagingService = true,
									MemoryStoreService = true,
									TextService = true,
									TextChatService = true,
									ContextActionService = true,
									GuiService = true,
									CollectionService = true,
									PhysicsService = true,
									PathfindingService = true,
									ContentProvider = true,
									InsertService = true,
									CoreGui = true,
									Teams = true,
									LocalizationService = true,
									ScriptContext = true,
									Stats = true,
									TestService = true,
									VRService = true,
									HapticService = true,
									GamepadService = true,
									AnalyticsService = true,
									AdService = true,
									AvatarEditorService = true,
									BadgeService = true,
									ChangeHistoryService = true,
									Chat = true,
									FriendService = true,
									GroupService = true,
									NetworkClient = true,
									NetworkServer = true,
									NotificationService = true,
									PointsService = true,
									PolicyService = true,
									RemoteConfigService = true,
									RobloxReplicatedStorage = true,
									Selection = true,
									SpatialVoiceService = true,
									StudioService = true,
									Terrain = true,
									TeleportService = true,
									AssetService = true,
									ScriptEditorService = true,
								}
								local function gameImport(svc)
									if ROBLOX_SERVICES[svc] then
										return 'game:GetService("' .. svc .. '")'
									else
										return "game." .. svc
									end
								end
								if idxCount == 1 then
									tag = kstr(ci1)
								elseif idxCount == 2 then
									local root = kstr(ci1)
									local leaf = kstr(ci2)
									if root == "game" then
										tag = gameImport(leaf)
									else
										tag = root .. "." .. leaf
									end
								elseif idxCount == 3 then
									local root = kstr(ci1)
									local mid = kstr(ci2)
									local leaf = kstr(ci3)
									if root == "game" then
										tag = gameImport(mid) .. "." .. leaf
									else
										tag = root .. "." .. mid .. "." .. leaf
									end
								end
								constValue = tag
							elseif constType == BT.LBC_CONSTANT_TABLE then
								local sz = reader:nextVarInt()
								local keys = {}
								for k = 1, sz do
									keys[k] = reader:nextVarInt() + 1
								end
								constValue = { size = sz, keys = keys }
							elseif constType == BT.LBC_CONSTANT_CLOSURE then
								constValue = reader:nextVarInt() + 1
							elseif constType == BT.LBC_CONSTANT_VECTOR then
								local x, y, z, w =
									reader:nextFloat(), reader:nextFloat(), reader:nextFloat(), reader:nextFloat()
								constValue = w == 0 and ("Vector3.new(" .. x .. "," .. y .. "," .. z .. ")")
									or ("vector.create(" .. x .. "," .. y .. "," .. z .. "," .. w .. ")")
							elseif constType == BT.LBC_CONSTANT_TABLE_WITH_CONSTANTS then
								local sz = reader:nextVarInt()
								local keys = {}
								for k = 1, sz do
									keys[k] = reader:nextVarInt() + 1
									reader:nextInt32()
								end
								constValue = { size = sz, keys = keys }
							elseif constType == BT.LBC_CONSTANT_INTEGER then
								local isNegative = reader:nextByte()
								local magnitude = reader:nextVarInt()
								constValue = (isNegative == 1) and -magnitude or magnitude
							elseif constType == BT.LBC_CONSTANT_CLASS_SHAPE then
								local classNameIdx = reader:nextVarInt()
								local propCount = reader:nextVarInt()
								local methodCount = reader:nextVarInt()
								local propNames, methodNames = {}, {}
								for k = 1, propCount do
									propNames[k] = stringTable[reader:nextVarInt()]
								end
								for k = 1, methodCount do
									methodNames[k] = stringTable[reader:nextVarInt()]
								end
								constValue = {
									className = stringTable[classNameIdx],
									properties = propNames,
									methods = methodNames,
								}
							elseif constType == BT.LBC_CONSTANT_VECTORD then
								local x, y, z, w =
									reader:nextDouble(), reader:nextDouble(), reader:nextDouble(), reader:nextDouble()
								constValue = w == 0 and ("Vector3.new(" .. x .. "," .. y .. "," .. z .. ")")
									or ("vector.create(" .. x .. "," .. y .. "," .. z .. "," .. w .. ")")
							end
							proto.constants[j] = { type = constType, value = constValue }
						end
						reader:mark(pfx .. "innerprotos:count")
						proto.sizeInnerProtos = reader:nextVarInt()
						for j = 1, proto.sizeInnerProtos do
							reader:mark(pfx .. "innerproto[" .. (j - 1) .. "/" .. proto.sizeInnerProtos .. "]")
							proto.innerProtos[j] = protoTable[reader:nextVarInt()]
						end
						reader:mark(pfx .. "lineDefined")
						proto.lineDefined = reader:nextVarInt()
						reader:mark(pfx .. "nameId")
						local nameId = reader:nextVarInt()
						proto.name = stringTable[nameId]
						reader:mark(pfx .. "hasLineInfo")
						local hasLineInfo = toBoolean(reader:nextByte())
						proto.hasLineInfo = hasLineInfo
						if hasLineInfo then
							reader:mark(pfx .. "lineinfo:gap")
							local lgap = reader:nextByte()
							local baselineSize = bit32.rshift(proto.sizeInstructions - 1, lgap) + 1
							local smallLineInfo, absLineInfo = {}, {}
							local lastOffset, lastLine = 0, 0
							reader:mark(pfx .. "lineinfo:small[0.." .. proto.sizeInstructions .. "]")
							for j = 1, proto.sizeInstructions do
								local b = reader:nextSignedByte()
								lastOffset += b
								smallLineInfo[j] = lastOffset
							end
							reader:mark(pfx .. "lineinfo:abs[0.." .. baselineSize .. "]")
							for j = 1, baselineSize do
								local lc = lastLine + reader:nextInt32()
								absLineInfo[j - 1] = lc
								lastLine = lc
							end
							local resultLineInfo = {}
							for j, line in ipairs(smallLineInfo) do
								local absIdx = bit32.rshift(j - 1, lgap)
								local absLine = absLineInfo[absIdx]
								local rl = line + absLine
								if lgap <= 1 and (-line == absLine) then
									rl += absLineInfo[absIdx + 1] or 0
								end
								if rl <= 0 then
									rl += 0x100
								end
								resultLineInfo[j] = rl
							end
							proto.lineInfoSize = lgap
							proto.instructionLineInfo = resultLineInfo
						end
						reader:mark(pfx .. "hasDebugInfo")
						local hasDebugInfo = toBoolean(reader:nextByte())
						proto.hasDebugInfo = hasDebugInfo
						if hasDebugInfo then
							reader:mark(pfx .. "debuglocals:count")
							local totalLocals = reader:nextVarInt()
							local debugLocals = {}
							for j = 1, totalLocals do
								reader:mark(pfx .. "debuglocal[" .. (j - 1) .. "/" .. totalLocals .. "]")
								debugLocals[j] = {
									name = stringTable[reader:nextVarInt()],
									startPC = reader:nextVarInt(),
									endPC = reader:nextVarInt(),
									register = reader:nextByte(),
								}
							end
							proto.debugLocals = debugLocals
							reader:mark(pfx .. "debugupvals:count")
							local totalUpvals = reader:nextVarInt()
							local debugUpvalues = {}
							for j = 1, totalUpvals do
								reader:mark(pfx .. "debugupval[" .. (j - 1) .. "/" .. totalUpvals .. "]")
								debugUpvalues[j] = { name = stringTable[reader:nextVarInt()] }
							end
							proto.debugUpvalues = debugUpvalues
						end
						if bytecodeVersion >= 11 then
							reader:mark(pfx .. "feedbackvec:count")
							local feedbackSize = reader:nextVarInt()
							for _ = 1, feedbackSize do
								reader:nextByte()
								reader:nextVarInt()
							end
						end
						if bytecodeVersion >= 12 then
							local LPF_INLINABLE = 8
							if proto.flags and bit32.btest(proto.flags, LPF_INLINABLE) then
								reader:mark(pfx .. "cost")
								proto.cost = reader:nextVarInt64()
							end
							local expectedEnd = protoStart + protoSize
							local here = reader:pos()
							if here > expectedEnd then
								error(
									string.format(
										"Proto %d over-read: cursor %d is past declared end %d (start %d, size %d). "
											.. "A field in this proto is being read wrongly.",
										protoId,
										here,
										expectedEnd,
										protoStart,
										protoSize
									),
									2
								)
							end
							reader:seek(expectedEnd)
						end
					end
				end
				readStringTable()
				if typeEncodingVersion == 3 then
					readUserdataTypes()
				end
				readProtoTable()
				reader:mark("mainProtoId")
				local mainProtoId = reader:nextVarInt()
				return mainProtoId, protoTable
			end
			local function organize()
				local mainProtoId, protoTable = disassemble()

				-- Luau bytecode can contain either the normal opcode IDs or this
				-- decompiler's multiplier-encoded IDs. Score both interpretations
				-- across every prototype, accounting for AUX words, then use the
				-- interpretation that produces the most coherent instruction stream.
				local function scoreOpcodeEncoding(opcodeMap)
					local score = 0
					for _, proto in protoTable do
						local instructions = proto.instructions
						local skipAux = false
						for _, instruction in ipairs(instructions) do
							if skipAux then
								skipAux = false
								continue
							end
							local opcode = Luau:INSN_OP(instruction)
							local info = opcodeMap[opcode]
							if info then
								score += 2
								skipAux = info.aux == true
							else
								score -= 1
							end
						end
					end
					return score
				end

				local rawOpcodeScore = scoreOpcodeEncoding(LuauRawOpcodeMap)
				local encodedOpcodeScore = scoreOpcodeEncoding(LuauEncodedOpCode)
				local opcodeMap = rawOpcodeScore > encodedOpcodeScore
					and LuauRawOpcodeMap
					or LuauEncodedOpCode

				local mainProto = protoTable[mainProtoId]
				mainProto.main = true
				local registerActions = {}
				local function baseProto(proto)
					local protoRegisterActions = {}
					registerActions[proto.id] = { proto = proto, actions = protoRegisterActions }
					local instructions = proto.instructions
					local innerProtos = proto.innerProtos
					local constants = proto.constants
					local captures = proto.captures
					local flags = proto.flags
					local function collectCaptures(baseIdx, p)
						local nup = p.numUpvalues
						if nup > 0 then
							local _c = p.captures
							for j = 1, nup do
								local cap = instructions[baseIdx + j]
								local ctype = Luau:INSN_A(cap)
								local sreg = Luau:INSN_B(cap)
								if ctype == LuauCaptureType.LCT_VAL or ctype == LuauCaptureType.LCT_REF then
									_c[j - 1] = sreg
								elseif ctype == LuauCaptureType.LCT_UPVAL then
									_c[j - 1] = captures[sreg]
								end
							end
						end
					end
					local function writeFlags()
						if type(flags) == "table" then
							return
						end
						local rawFlags = type(flags) == "number" and flags or 0
						local df = {}
						if proto.main then
							df.native = toBoolean(bit32.band(rawFlags, LuauProtoFlag.LPF_NATIVE_MODULE))
						else
							df.native = toBoolean(bit32.band(rawFlags, LuauProtoFlag.LPF_NATIVE_FUNCTION))
							df.cold = toBoolean(bit32.band(rawFlags, LuauProtoFlag.LPF_NATIVE_COLD))
						end
						flags = df
						proto.flags = df
					end
					local function writeInstructions()
						local auxSkip = false
						local currentInstructionPC = 0
						local function reg(act, regs, extra, hide)
							table.insert(
								protoRegisterActions,
								{ usedRegisters = regs or {}, extraData = extra, opCode = act, hide = hide, bytecodePC = currentInstructionPC }
							)
						end
						for idx, instruction in ipairs(instructions) do
							if auxSkip then
								auxSkip = false
								continue
							end
							currentInstructionPC = idx
							local oci = opcodeMap[Luau:INSN_OP(instruction)]
							if not oci then
								error(
									string.format(
										"Unknown Luau opcode %d at prototype %d instruction %d",
										Luau:INSN_OP(instruction),
										proto.id,
										idx
									)
								)
							end
							local opn = oci.name
							local opt = oci.type
							local isAux = oci.aux == true
							local A, B, C, sD, D, E, aux
							if opt == "A" then
								A = Luau:INSN_A(instruction)
							elseif opt == "E" then
								E = Luau:INSN_E(instruction)
							elseif opt == "AB" then
								A = Luau:INSN_A(instruction)
								B = Luau:INSN_B(instruction)
							elseif opt == "AC" then
								A = Luau:INSN_A(instruction)
								C = Luau:INSN_C(instruction)
							elseif opt == "ABC" then
								A = Luau:INSN_A(instruction)
								B = Luau:INSN_B(instruction)
								C = Luau:INSN_C(instruction)
							elseif opt == "AD" then
								A = Luau:INSN_A(instruction)
								D = Luau:INSN_D(instruction)
							elseif opt == "AsD" then
								A = Luau:INSN_A(instruction)
								sD = Luau:INSN_sD(instruction)
							elseif opt == "sD" then
								sD = Luau:INSN_sD(instruction)
							end
							if isAux then
								auxSkip = true
								reg(oci, nil, nil, true)
								aux = instructions[idx + 1]
							end
							local st = not true
							if opn == "NOP" or opn == "BREAK" or opn == "NATIVECALL" then
								reg(oci, nil, nil, st)
							elseif opn == "LOADNIL" then
								reg(oci, { A })
							elseif opn == "LOADB" then
								reg(oci, { A }, { B, C })
							elseif opn == "LOADN" then
								reg(oci, { A }, { sD })
							elseif opn == "LOADK" then
								reg(oci, { A }, { D })
							elseif opn == "MOVE" then
								reg(oci, { A, B })
							elseif opn == "GETGLOBAL" or opn == "SETGLOBAL" then
								reg(oci, { A }, { aux })
							elseif opn == "GETUPVAL" or opn == "SETUPVAL" then
								reg(oci, { A }, { B })
							elseif opn == "CLOSEUPVALS" then
								reg(oci, { A }, nil, st)
							elseif opn == "GETIMPORT" then
								reg(oci, { A }, { D, aux })
							elseif opn == "GETTABLE" or opn == "SETTABLE" then
								reg(oci, { A, B, C })
							elseif opn == "GETTABLEKS" or opn == "SETTABLEKS" then
								reg(oci, { A, B }, { C, aux })
							elseif opn == "GETTABLEN" or opn == "SETTABLEN" then
								reg(oci, { A, B }, { C })
							elseif opn == "NEWCLOSURE" then
								reg(oci, { A }, { D })
								local p2 = innerProtos[D + 1]
								if p2 then
									collectCaptures(idx, p2)
									baseProto(p2)
								end
							elseif opn == "DUPCLOSURE" then
								reg(oci, { A }, { D })
								local c = constants[D + 1]
								if c then
									local p2 = protoTable[c.value - 1]
									if p2 then
										collectCaptures(idx, p2)
										baseProto(p2)
									end
								end
							elseif opn == "NAMECALL" then
								reg(oci, { A, B }, { C, aux }, st)
							elseif opn == "CALL" then
								reg(oci, { A }, { B, C })
							elseif opn == "RETURN" then
								reg(oci, { A }, { B })
							elseif opn == "JUMP" or opn == "JUMPBACK" then
								reg(oci, {}, { sD })
							elseif opn == "JUMPIF" or opn == "JUMPIFNOT" then
								reg(oci, { A }, { sD })
							elseif
								opn == "JUMPIFEQ"
								or opn == "JUMPIFLE"
								or opn == "JUMPIFLT"
								or opn == "JUMPIFNOTEQ"
								or opn == "JUMPIFNOTLE"
								or opn == "JUMPIFNOTLT"
							then
								reg(oci, { A, aux }, { sD })
							elseif
								opn == "ADD"
								or opn == "SUB"
								or opn == "MUL"
								or opn == "DIV"
								or opn == "MOD"
								or opn == "POW"
							then
								reg(oci, { A, B, C })
							elseif
								opn == "ADDK"
								or opn == "SUBK"
								or opn == "MULK"
								or opn == "DIVK"
								or opn == "MODK"
								or opn == "POWK"
							then
								reg(oci, { A, B }, { C })
							elseif opn == "AND" or opn == "OR" then
								reg(oci, { A, B, C })
							elseif opn == "ANDK" or opn == "ORK" then
								reg(oci, { A, B }, { C })
							elseif opn == "CONCAT" then
								local regs = { A }
								for r = B, C do
									table.insert(regs, r)
								end
								reg(oci, regs)
							elseif opn == "NOT" or opn == "MINUS" or opn == "LENGTH" then
								reg(oci, { A, B })
							elseif opn == "NEWTABLE" then
								reg(oci, { A }, { B, aux })
							elseif opn == "DUPTABLE" then
								reg(oci, { A }, { D })
							elseif opn == "SETLIST" then
								if C ~= 0 then
									-- Luau's fixed SETLIST count uses count+1 encoding; zero
									-- denotes the open/top-of-stack form.
									local regs = { A, B }
									for k = 1, math.max(0, C - 2) do
										table.insert(regs, B + k)
									end
									reg(oci, regs, { aux, C })
								else
									reg(oci, { A, B }, { aux, C })
								end
							elseif opn == "FORNPREP" then
								reg(oci, { A, A + 1, A + 2 }, { sD })
							elseif opn == "FORNLOOP" then
								reg(oci, { A }, { sD })
							elseif opn == "FORGLOOP" then
								local nv = bit32.band(aux or 0, 0xFF)
								local regs = {}
								for k = 1, nv do
									table.insert(regs, A + 2 + k)
								end
								reg(oci, regs, { sD, aux, A })
							elseif opn == "FORGPREP_INEXT" or opn == "FORGPREP_NEXT" then
								reg(oci, { A, A + 1 })
							elseif opn == "FORGPREP" then
								reg(oci, { A }, { sD })
							elseif opn == "GETVARARGS" then
								if B ~= 0 then
									local regs = { A }
									for k = 1, B - 1 do
										table.insert(regs, A + k)
									end
									reg(oci, regs, { B })
								else
									reg(oci, { A }, { B })
								end
							elseif opn == "PREPVARARGS" then
								reg(oci, {}, { A }, st)
							elseif opn == "LOADKX" then
								reg(oci, { A }, { aux })
							elseif opn == "JUMPX" then
								reg(oci, {}, { E })
							elseif opn == "COVERAGE" then
								reg(oci, {}, { E }, st)
							elseif
								opn == "JUMPXEQKNIL"
								or opn == "JUMPXEQKB"
								or opn == "JUMPXEQKN"
								or opn == "JUMPXEQKS"
							then
								reg(oci, { A }, { sD, aux })
							elseif opn == "CAPTURE" then
								reg(oci, nil, nil, st)
							elseif opn == "SUBRK" or opn == "DIVRK" then
								reg(oci, { A, C }, { B })
							elseif opn == "IDIV" then
								reg(oci, { A, B, C })
							elseif opn == "IDIVK" then
								reg(oci, { A, B }, { C })
							elseif opn == "GETUDATAKS" then
								reg(oci, { A, B }, { C, aux })
							elseif opn == "SETUDATAKS" then
								reg(oci, { A, B }, { C, aux })
							elseif opn == "NAMECALLUDATA" then
								reg(oci, { A, B }, { C, aux }, st)
							elseif opn == "NEWCLASSMEMBER" then
								reg(oci, { A, C }, { aux })
							elseif opn == "CALLFB" then
								reg(oci, { A }, { B, C, aux })
							elseif opn == "CMPPROTO" then
								reg(oci, { A }, { sD, aux })
							elseif opn == "FASTCALL" then
								reg(oci, {}, { A, C }, st)
							elseif opn == "FASTCALL1" then
								reg(oci, { B }, { A, C }, st)
							elseif opn == "FASTCALL2" then
								local r2 = bit32.band(aux or 0, 0xFF)
								reg(oci, { B, r2 }, { A, C }, st)
							elseif opn == "FASTCALL2K" then
								reg(oci, { B }, { A, C, aux }, st)
							elseif opn == "FASTCALL3" then
								local r2 = bit32.band(aux or 0, 0xFF)
								local r3 = bit32.band(bit32.rshift(aux or 0, 8), 0xFF)
								reg(oci, { B, r2, r3 }, { A, C }, st)
							end
						end
					end
					writeFlags()
					writeInstructions()
				end
				baseProto(mainProto)
				return mainProtoId, registerActions, protoTable
			end
			local function finalize(mainProtoId, registerActions, protoTable)
				local finalResult = ""
				local totalParameters = 0
				local usedGlobals = {}
				local usedGlobalsSet = {}
				local function isValidGlobal(key)
					if usedGlobalsSet[key] then
						return false
					end
					return not isGlobal(key)
				end
				local function processResult(res)
					local embed = ""
					if true and #usedGlobals > 0 then
						embed = string.format(Strings.USED_GLOBALS, table.concat(usedGlobals, ", "))
					end
					return embed .. res
				end
				if "disasm" == "disasm" then
					local resultParts = {}
					local function emitRaw(s)
						resultParts[#resultParts + 1] = s
					end
					local function emit(s)
						resultParts[#resultParts + 1] = s:gsub("\n*$", "") .. "\n"
					end
					local function writeActions(protoActions)
						local openCallTail = nil
	local iteratorCalls = {}
						local actions = protoActions.actions
						local proto = protoActions.proto
						local lineInfo = proto.instructionLineInfo
						local inner = proto.innerProtos
						local consts = proto.constants
						local caps = proto.captures
						local pflags = proto.flags
						local numParams = proto.numParams
						local flow = { numeric = {}, generic = {}, backedges = {}, targets = {} }
						-- Source-emission indices are not bytecode PCs: AUX-bearing
						-- instructions create hidden marker actions, and those markers share
						-- the bytecode PC with the visible semantic action. Prefer the
						-- visible action when translating a bytecode jump destination.
						local actionAtBytecodePC = {}
						local maxBytecodePC = -1
						for actionIndex, action in ipairs(actions) do
							local bytecodePC = action.bytecodePC
							if type(bytecodePC) == "number" then
								if bytecodePC > maxBytecodePC then maxBytecodePC = bytecodePC end
								local prior = actionAtBytecodePC[bytecodePC]
								if prior == nil or (actions[prior] and actions[prior].hide and not action.hide) then
									actionAtBytecodePC[bytecodePC] = actionIndex
								end
							end
						end
						local function jumpTarget(pc, delta)
							-- Luau jump offsets are relative to the bytecode instruction
							-- after the jump, not to the filtered action-array index.
							local action = actions[pc]
							local bytecodePC = action and action.bytecodePC
							if type(bytecodePC) == "number" and type(delta) == "number" then
								local target = actionAtBytecodePC[bytecodePC + delta + 1]
								if target then return target end
								if bytecodePC + delta + 1 > maxBytecodePC then return #actions + 1 end
							end
							-- Conservative compatibility fallback for malformed or unmapped
							-- targets; valid decoded targets take the bytecode-PC path above.
							return pc + (delta or 0) + 1
						end
						local CONDITIONAL_JUMPS = {
							JUMPIF = true, JUMPIFNOT = true, JUMPIFEQ = true, JUMPIFLE = true,
							JUMPIFLT = true, JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
							JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
						}
						-- Build an instruction-level CFG before attempting source structuring.
						-- Action indices are used here to stay compatible with the current
						-- action stream; AUX words have already been consumed by organize().
						local function buildControlFlowGraph()
							local count = #actions
							local cfg = {
								blocks = {}, blockAt = {}, edges = {}, predecessors = {},
								successors = {}, dominators = {}, postDominators = {},
								naturalLoops = {}, naturalBackedges = {}, leaders = {},
							}
							local leaders = { [1] = true }
							local targetAt = {}
							local actionAtBytecodePC = {}
							for actionIndex, action in ipairs(actions) do
								if type(action.bytecodePC) == "number" then
									local prior = actionAtBytecodePC[action.bytecodePC]
									if prior == nil or (actions[prior] and actions[prior].hide and not action.hide) then
										actionAtBytecodePC[action.bytecodePC] = actionIndex
									end
								end
							end
							local unconditional = { JUMP = true, JUMPBACK = true, JUMPX = true }
							local terminal = { RETURN = true, RETURN0 = true, RETURN1 = true }
							local function isConditional(op)
								return CONDITIONAL_JUMPS[op] == true
									or op == "FORNPREP" or op == "FORNLOOP"
									 or op == "FORGPREP" or op == "FORGPREP_INEXT"
									 or op == "FORGPREP_NEXT" or op == "FORGLOOP"
								end
							for pc, act in ipairs(actions) do
								local op = act.opCode and act.opCode.name
								local delta = act.extraData and act.extraData[1]
								local hasTarget = unconditional[op] or isConditional(op)
								if hasTarget and type(delta) == "number" then
									local bytecodePC = act.bytecodePC or pc
									local targetBytecodePC = bytecodePC + delta + 1
									local target = actionAtBytecodePC[targetBytecodePC]
									if target and target >= 1 and target <= count then
										targetAt[pc] = target
										leaders[target] = true
									end
								end
								if unconditional[op] or isConditional(op) or terminal[op] then
									if pc < count then leaders[pc + 1] = true end
								end
							end
							local leaderList = {}
							for pc in pairs(leaders) do leaderList[#leaderList + 1] = pc end
							table.sort(leaderList)
							cfg.leaders = leaderList
							for i, startPC in ipairs(leaderList) do
								local block = { id = i, start = startPC, finish = (leaderList[i + 1] or (count + 1)) - 1 }
								cfg.blocks[i] = block
								for pc = block.start, block.finish do cfg.blockAt[pc] = i end
								cfg.successors[i], cfg.predecessors[i] = {}, {}
							end
							local function addEdge(fromId, toId, kind)
								if not fromId or not toId then return end
								local list = cfg.successors[fromId]
								for _, edge in ipairs(list) do
									if edge.to == toId then return end
								end
								local edge = { from = fromId, to = toId, kind = kind }
								list[#list + 1] = edge
								cfg.edges[#cfg.edges + 1] = edge
								cfg.predecessors[toId][#cfg.predecessors[toId] + 1] = fromId
							end
							for blockId, block in ipairs(cfg.blocks) do
								local last = actions[block.finish]
								local op = last and last.opCode and last.opCode.name
								local target = targetAt[block.finish]
								local nextBlock = blockId < #cfg.blocks and (blockId + 1) or nil
								if unconditional[op] then
									if target then addEdge(blockId, cfg.blockAt[target], "jump") end
								elseif terminal[op] then
									-- No successor: return terminates this path.
								elseif isConditional(op) then
									if target then addEdge(blockId, cfg.blockAt[target], "taken") end
									if nextBlock then addEdge(blockId, nextBlock, "fallthrough") end
								else
									if nextBlock then addEdge(blockId, nextBlock, "fallthrough") end
								end
							end
							local blockCount = #cfg.blocks
							local all = {}
							for i = 1, blockCount do all[i] = true end
							for i = 1, blockCount do
								cfg.dominators[i] = i == 1 and { [1] = true } or table.clone(all)
								cfg.postDominators[i] = table.clone(all)
							end
							local changed = true
							while changed do
								changed = false
								for i = 2, blockCount do
									local preds = cfg.predecessors[i]
									local nextSet = {}
									if #preds > 0 then
										for k in pairs(cfg.dominators[preds[1]]) do nextSet[k] = true end
										for pi = 2, #preds do
											for k in pairs(nextSet) do if not cfg.dominators[preds[pi]][k] then nextSet[k] = nil end end
										end
									end
									 nextSet[i] = true
									local old = cfg.dominators[i]
									for k in pairs(old) do if not nextSet[k] then changed = true end end
									for k in pairs(nextSet) do if not old[k] then changed = true end end
									cfg.dominators[i] = nextSet
								end
							end
							-- Add a virtual exit node for post-dominator analysis.
							local exitId = blockCount + 1
							local postAll = {}
							for i = 1, exitId do postAll[i] = true end
							cfg.postDominators[exitId] = { [exitId] = true }
							local postChanged = true
							while postChanged do
								postChanged = false
								for i = blockCount, 1, -1 do
									local succs = cfg.successors[i]
									local nextSet = {}
									if #succs == 0 then
										for k in pairs(cfg.postDominators[exitId]) do nextSet[k] = true end
									else
										for k in pairs(cfg.postDominators[succs[1].to]) do nextSet[k] = true end
										for si = 2, #succs do
											for k in pairs(nextSet) do if not cfg.postDominators[succs[si].to][k] then nextSet[k] = nil end end
										end
									end
									 nextSet[i] = true
									local old = cfg.postDominators[i]
									for k in pairs(old) do if not nextSet[k] then postChanged = true end end
									for k in pairs(nextSet) do if not old[k] then postChanged = true end end
									if postChanged then cfg.postDominators[i] = nextSet end
								end
							end
							for _, edge in ipairs(cfg.edges) do
								if edge.to <= edge.from and cfg.dominators[edge.from][edge.to] then
									local loop = { header = edge.to, latch = edge.from, blocks = { [edge.to] = true, [edge.from] = true } }
									local stack = { edge.from }
									while #stack > 0 do
										local node = table.remove(stack)
										if node ~= edge.to then
											for _, pred in ipairs(cfg.predecessors[node]) do
												if not loop.blocks[pred] then loop.blocks[pred] = true; stack[#stack + 1] = pred end
											end
										end
									end
									cfg.naturalLoops[#cfg.naturalLoops + 1] = loop
									local tailPC = cfg.blocks[edge.from].finish
									local headPC = cfg.blocks[edge.to].start
									cfg.naturalBackedges[tailPC] = headPC
								end
							end
							cfg.exitBlock = exitId
							return cfg
						end
						local cfg = buildControlFlowGraph()
						flow.cfg = cfg
						for pc, act in ipairs(actions) do
							local op = act.opCode and act.opCode.name
							local delta = act.extraData and act.extraData[1]
							if
								type(delta) == "number"
								and (
									op == "FORNPREP"
									or op == "FORGPREP"
									or op == "FORGPREP_INEXT"
									or op == "FORGPREP_NEXT"
									or op == "FORNLOOP"
									or op == "FORGLOOP"
									or op == "JUMPBACK"
									or op == "JUMP"
								)
							then
								local dest = jumpTarget(pc, delta)
								if dest >= 1 and dest <= #actions + 1 then
									flow.targets[dest] = true
									if dest <= pc then
										flow.backedges[pc] = dest
									end
									if op == "FORNPREP" then
										flow.numeric[pc] = dest
									end
									if op == "FORGPREP" then
										flow.generic[pc] = dest
									end
								end
							end
						end
						-- Prefer dominance-validated natural backedges. Keep the raw set as a
						-- fallback for irreducible or partially decoded control flow.
						local rawBackedges = flow.backedges
						if next(cfg.naturalBackedges) ~= nil then
							flow.backedges = cfg.naturalBackedges
						else
							flow.backedges = rawBackedges
						end
						-- Recognize a common if/else shape: a conditional jump to the else
						-- arm, with an unconditional forward JUMP immediately before it.
						local elseBranches, elseJumpIndices = {}, {}
						local function previousVisibleAction(index)
							local j = index - 1
							while j >= 1 and actions[j] and actions[j].hide do j -= 1 end
							return j >= 1 and j or nil
						end
						local function nextVisibleAction(index)
							local j = index + 1
							while j <= #actions and actions[j] and actions[j].hide do j += 1 end
							return j <= #actions and j or nil
						end
						for pc, act in ipairs(actions) do
							local op = act.opCode and act.opCode.name
							local delta = act.extraData and act.extraData[1]
							if CONDITIONAL_JUMPS[op] and type(delta) == "number" then
								local elseStart = jumpTarget(pc, delta)
								local skipIndex, elseEnd
								for candidate = pc + 1, elseStart - 1 do
									local ca = actions[candidate]
									if ca and not ca.hide and ca.opCode and ca.opCode.name == "JUMP" then
										local d = ca.extraData and ca.extraData[1]
										if type(d) == "number" then
											local target = jumpTarget(candidate, d)
											if target > elseStart and target <= #actions + 1 then skipIndex, elseEnd = candidate, target end
										end
									end
								end
								if skipIndex and elseEnd then
									elseBranches[elseStart] = elseEnd
									elseJumpIndices[skipIndex] = true
								end
							end
						end
						if ZUK_TRACE_FLOW then
							local hasControlFlow = false
							for _, a in ipairs(actions) do
								local n = a.opCode and a.opCode.name or "?"
								if n == "JUMPBACK" or n == "FORNPREP" or n == "FORGPREP" then
									hasControlFlow = true
									break
								end
							end
							if hasControlFlow then
								print(
									"[FLOW TRACE] proto="
										.. tostring(proto.debugName or proto.name or "anonymous")
										.. " instructions="
										.. tostring(#actions)
								)
								for pc, a in ipairs(actions) do
									local n = a.opCode and a.opCode.name or "?"
									if n:match("^JUMP") or n:match("^FOR") or n == "RETURN" then
										local rr, ee = {}, {}
										for k, v in ipairs(a.usedRegisters or {}) do
											rr[#rr + 1] = tostring(k) .. ":" .. tostring(v)
										end
										for k, v in ipairs(a.extraData or {}) do
											ee[#ee + 1] = tostring(k) .. ":" .. tostring(v)
										end
										local delta = a.extraData and a.extraData[1]
										local target = type(delta) == "number"
												and (n:match("^JUMP") or n:match("^FOR"))
												and (pc + delta + 1)
											or "-"
										print(
											"[FLOW] pc="
												.. pc
												.. " op="
												.. n
												.. " regs={"
												.. table.concat(rr, ",")
												.. "} extra={"
												.. table.concat(ee, ",")
												.. "} target="
												.. tostring(target)
										)
									end
								end
							end
						end
						if ZUK_TRACE_TABLES then
							local interesting = {
								NEWTABLE = true,
								DUPTABLE = true,
								SETTABLE = true,
								SETTABLEKS = true,
								SETTABLEN = true,
								SETLIST = true,
							}
							local found = false
							for _, a in ipairs(actions) do
								if a.opCode and interesting[a.opCode.name] then
									found = true
									break
								end
							end
							if found then
								print(
									"[ZUK TABLE] proto="
										.. tostring(proto.debugName or proto.name or "main")
										.. " actions="
										.. tostring(#actions)
								)
								for pc, a in ipairs(actions) do
									local op = a.opCode and a.opCode.name or "?"
									if
										interesting[op]
										or op == "LOADK"
										or op == "LOADN"
										or op == "LOADB"
										or op == "LOADNIL"
										or op == "MOVE"
										or op == "GETIMPORT"
										or (
											(
												proto.debugName == nil
												or proto.debugName == ""
												or proto.debugName == "main"
											) and pc <= 22
										)
									then
										local rr, ee = {}, {}
										for k, v in ipairs(a.usedRegisters or {}) do
											rr[#rr + 1] = tostring(k) .. ":" .. tostring(v)
										end
										for k, v in ipairs(a.extraData or {}) do
											ee[#ee + 1] = tostring(k) .. ":" .. tostring(v)
										end
										local detail = ""
										if op == "LOADK" then
											local c = consts[(a.extraData or {})[1] + 1]
											if c then
												detail = " value=" .. tostring(c.value)
											end
										elseif op == "DUPTABLE" then
											local c = consts[((a.extraData or {})[1] or -1) + 1]
											if c and type(c.value) == "table" then
												local names = {}
												for _, keyIndex in ipairs(c.value.keys or {}) do
													local kc = consts[keyIndex]
													names[#names + 1] = tostring(kc and kc.value or "?")
												end
												detail = " template_keys={"
													.. table.concat(names, ",")
													.. "} (not initialized values)"
											end
										elseif op == "SETTABLEKS" then
											local c = consts[((a.extraData or {})[2] or -1) + 1]
											if c then
												detail = " key=" .. tostring(c.value)
											end
										end
										print(
											"[ZUK TABLE] pc="
												.. pc
												.. " op="
												.. op
												.. " hidden="
												.. tostring(a.hide == true)
												.. " regs={"
												.. table.concat(rr, ",")
												.. "} extra={"
												.. table.concat(ee, ",")
												.. "}"
												.. detail
										)
									end
								end
							end
						end
						local diagnosticName = tostring(proto.debugName or proto.name or "")
						if
							ZUK_TRACE_FLOW
							and (
								diagnosticName == "repeatTest"
								or diagnosticName == "robloxTest"
								or diagnosticName == "numericLoop"
							)
						then
							print("[ZUK V20] proto=" .. diagnosticName .. " actions=" .. #actions)
							for pc, a in ipairs(actions) do
								local rr, ee = {}, {}
								for k, v in ipairs(a.usedRegisters or {}) do
									rr[#rr + 1] = k .. ":" .. tostring(v)
								end
								for k, v in ipairs(a.extraData or {}) do
									ee[#ee + 1] = k .. ":" .. tostring(v)
								end
								local op = a.opCode and a.opCode.name or "?"
								local d = a.extraData and a.extraData[1]
								local target = (op:match("^JUMP") or op:match("^FOR"))
										and type(d) == "number"
										and tostring(pc + d + 1)
									or "-"
								print(
									"[ZUK V20] pc="
										.. pc
										.. " op="
										.. op
										.. " hidden="
										.. tostring(a.hide == true)
										.. " regs={"
										.. table.concat(rr, ",")
										.. "} extra={"
										.. table.concat(ee, ",")
										.. "} target="
										.. target
								)
							end
						end
						local loopStarts, loopEnds, loopTests = {}, {}, {}
						local numericLoopVars = {}
						local genericLoopVars = {}
						local function isCond(op)
							return op == "JUMPIF"
								or op == "JUMPIFNOT"
								or op == "JUMPIFEQ"
								or op == "JUMPIFLE"
								or op == "JUMPIFLT"
								or op == "JUMPIFNOTEQ"
								or op == "JUMPIFNOTLE"
								or op == "JUMPIFNOTLT"
						end
						for tail, startPC in pairs(flow.backedges) do
							local back = actions[tail]
							if back.opCode.name == "JUMPBACK" and startPC < tail and not loopStarts[startPC] then
								local candidate, kind
								for j = startPC, tail - 1 do
									local a = actions[j]
									local n = a.opCode and a.opCode.name
									local d = a.extraData and a.extraData[1]
									if not a.hide and isCond(n) and type(d) == "number" and j + d + 1 > tail then
										if not candidate or j > candidate then
											candidate = j
										end
									end
								end
								if candidate then
									kind = (candidate >= tail - 2) and "repeat" or "while"
									loopStarts[startPC] = kind
									loopEnds[tail] = kind
									loopTests[candidate] = kind
								end
							end
						end
						local jumpMarkers = {}
						local function makeJump(idx)
							jumpMarkers[idx] = (jumpMarkers[idx] or 0) + 1
						end
						local indentLevel = 0
						local function ind()
							return string.rep("\t", indentLevel)
						end
						local function handleJumps(idx)
							local n = jumpMarkers[idx]
							if n then
								jumpMarkers[idx] = nil
								for _ = 1, n do
									indentLevel = math.max(0, indentLevel - 1)
									local elseEnd = elseBranches[idx]
									if elseEnd then
										elseBranches[idx] = nil
										emit(ind() .. "else")
										indentLevel += 1
										jumpMarkers[elseEnd] = (jumpMarkers[elseEnd] or 0) + 1
									else
										emit(ind() .. "end\n")
									end
								end
							end
						end
						totalParameters += numParams
						if proto.main and pflags and pflags.native then
							emit("--!native\n")
						end
						local function buildRegNames(instrIdx)
							local names = {}
							if proto.debugLocals then
								-- Debug-local ranges are bytecode PCs (zero-based, end-exclusive),
								-- while the emitter addresses actions (one-based, with AUX markers).
								-- Translate through the visible action's original bytecode PC.
								local action = actions[instrIdx]
								local pc = action and action.bytecodePC
								if type(pc) == "number" then pc -= 1 else pc = (instrIdx or 1) - 1 end
								for _, dl in ipairs(proto.debugLocals) do
									if pc >= dl.startPC and pc < dl.endPC then
										names[dl.register] = dl.name
									end
								end
							end
							return names
						end
						local function fmtUpv(r)
							if r == nil then
								return "upv_?"
							end
							if proto._captureNames and proto._captureNames[r] then
								return proto._captureNames[r]
							end
							local du = proto.debugUpvalues
							if du and du[r + 1] and du[r + 1].name ~= "" then
								return du[r + 1].name
							end
							return "upv_" .. tostring(r)
						end
						-- Opcode semantics for the register action format produced by writeInstructions().
						-- usedRegisters contains a mixture of destination and operand registers; it is
						-- NOT a generic read/write list. Keep these rules explicit and conservative.
						local function getSourceRegisters(opName, ur2, ed2)
							ur2, ed2 = ur2 or {}, ed2 or {}
							local a, b, c = ur2[1], ur2[2], ur2[3]
							local out = {}
							local function add(r)
								if type(r) == "number" then out[#out + 1] = r end
							end
							local function range(first, count)
								if type(first) == "number" and type(count) == "number" and count > 0 then
									for r = first, first + count - 1 do add(r) end
								end
							end

							if opName == "MOVE" then add(b)
							elseif opName == "SETGLOBAL" or opName == "SETUPVAL" then add(a)
							elseif opName == "GETTABLE" then add(b); add(c)
							elseif opName == "SETTABLE" then add(a); add(b); add(c)
							elseif opName == "GETTABLEKS" or opName == "GETTABLEN" then add(b)
							elseif opName == "SETTABLEKS" or opName == "SETTABLEN" then add(a); add(b)
							elseif opName == "NAMECALL" or opName == "NAMECALLUDATA" then add(b)
							elseif opName == "CALL" then
								-- B is the number of call-frame registers, including the callee.
								range(a, ed2[1] and math.max(1, ed2[1]) or 1)
							elseif opName == "CALLFB" then
								-- CALLFB shares CALL's frame layout; B counts frame registers.
								range(a, ed2[1] and math.max(1, ed2[1]) or 1)
							elseif opName == "RETURN" then
								local count = ed2[1] or 1
								if count == 0 then add(a) else range(a, math.max(0, count - 1)) end
							elseif opName == "JUMPIF" or opName == "JUMPIFNOT"
								or opName == "JUMPXEQKNIL" or opName == "JUMPXEQKB"
								or opName == "JUMPXEQKN" or opName == "JUMPXEQKS" then
								add(a)
							elseif opName == "JUMPIFEQ" or opName == "JUMPIFLE" or opName == "JUMPIFLT"
								or opName == "JUMPIFNOTEQ" or opName == "JUMPIFNOTLE" or opName == "JUMPIFNOTLT" then
								-- AUX is an encoded operand, not a register number.
								add(a)
							elseif opName == "ADD" or opName == "SUB" or opName == "MUL"
								or opName == "DIV" or opName == "MOD" or opName == "POW"
								or opName == "IDIV" or opName == "AND" or opName == "OR" then
								add(b); add(c)
							elseif opName == "ADDK" or opName == "SUBK" or opName == "MULK"
								or opName == "DIVK" or opName == "MODK" or opName == "POWK"
								or opName == "IDIVK" or opName == "ANDK" or opName == "ORK" then
								add(b)
							elseif opName == "SUBRK" or opName == "DIVRK" then add(c)
							elseif opName == "CONCAT" then
								if type(b) == "number" and type(c) == "number" then
									for r = b, c do add(r) end
								end
							elseif opName == "NOT" or opName == "MINUS" or opName == "LENGTH" then add(b)
							elseif opName == "SETLIST" then
								add(a)
								local encodedCount = ed2[2] or 0
								if encodedCount == 0 then add(b) else range(b, math.max(0, encodedCount - 1)) end
							elseif opName == "FORNPREP" then
								range(a, 3)
							elseif opName == "FORNLOOP" then
								range(a, 3)
							elseif opName == "FORGLOOP" then
								-- The loop base is carried in extraData[3]; usedRegisters are outputs.
								range(ed2[3], 3)
							elseif opName == "FORGPREP" or opName == "FORGPREP_INEXT" or opName == "FORGPREP_NEXT" then
								range(a, 3)
							elseif opName == "GETUDATAKS" then add(b)
							elseif opName == "SETUDATAKS" then add(a); add(b)
							elseif opName == "NEWCLASSMEMBER" then add(a); add(c)
							elseif opName == "FASTCALL1" or opName == "FASTCALL2K" then add(a)
							elseif opName == "FASTCALL2" or opName == "FASTCALL3" then
								add(a); add(b)
								if opName == "FASTCALL3" then add(c) end
							end
							return out
						end

						local NO_DEF_OPS = {
							SETTABLE = true, SETTABLEKS = true, SETTABLEN = true,
							SETGLOBAL = true, SETUPVAL = true, SETUDATAKS = true,
							RETURN = true, RETURN0 = true, RETURN1 = true,
							JUMP = true, JUMPBACK = true, JUMPIF = true, JUMPIFNOT = true,
							JUMPIFEQ = true, JUMPIFLE = true, JUMPIFLT = true,
							JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
							JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
							CLOSEUPVALS = true, SETLIST = true,
							FORGPREP = true, FORGPREP_INEXT = true, FORGPREP_NEXT = true,
							COVERAGE = true, CAPTURE = true, NOP = true, BREAK = true,
							PREPVARARGS = true, CMPPROTO = true, FASTCALL = true,
							FASTCALL1 = true, FASTCALL2 = true, FASTCALL2K = true, FASTCALL3 = true,
							JUMPX = true, NEWCLASSMEMBER = true, NATIVECALL = true,
						}
						local function getDefinedRegisters(opName, ur2, ed2)
							ur2, ed2 = ur2 or {}, ed2 or {}
							local a = ur2[1]
							local defs = {}
							local function range(first, count)
								if type(first) == "number" and type(count) == "number" and count > 0 then
									for r = first, first + count - 1 do defs[#defs + 1] = r end
								end
							end
							if NO_DEF_OPS[opName] then return defs end
							if opName == "CALL" or opName == "CALLFB" then
								local count = ed2[2] or 1 -- C: result count plus one; zero means open results.
								if count == 0 then return { a } end
								range(a, math.max(0, count - 1))
								return defs
							elseif opName == "GETVARARGS" then
								local count = ed2[1] or 1
								if count == 0 then return { a } end
								range(a, math.max(0, count - 1))
								return defs
							elseif opName == "NAMECALL" or opName == "NAMECALLUDATA" then
								-- NAMECALL prepares the callable and implicit self in A and A+1.
								range(a, 2)
								return defs
							elseif opName == "FORGLOOP" then
								-- writeInstructions stores the actual output registers in usedRegisters.
								for _, r in ipairs(ur2) do
									if type(r) == "number" then defs[#defs + 1] = r end
								end
								return defs
							elseif opName == "FORNLOOP" then
								-- The loop instruction updates the internal index and visible loop variable.
								range(a, 1)
								range(a and (a + 3), 1)
								return defs
							end
							if type(a) == "number" then defs[1] = a end
							return defs
						end
						-- Register data-flow is computed over the CFG rather than assuming that
						-- the previous textual assignment is always the reaching value.
						local function buildRegisterDataFlow()
							local rf = { instructions = {}, blocks = {}, definitions = {}, definitionInfo = {}, usesByDefinition = {}, uninitializedUses = {}, phiCandidates = {} }
							local definitionsByRegister = {}
							local function addSet(set, value) set[value] = true end
							for blockId, block in ipairs(cfg.blocks) do
								rf.blocks[blockId] = { use = {}, def = {}, liveIn = {}, liveOut = {}, inDefs = {}, outDefs = {}, gen = {}, kill = {} }
								local state = rf.blocks[blockId]
								for ai = block.start, block.finish do
									local act = actions[ai]
									local op = act.opCode and act.opCode.name
									local uses = getSourceRegisters(op, act.usedRegisters, act.extraData)
									local defs = getDefinedRegisters(op, act.usedRegisters, act.extraData)
									local info = { block = blockId, uses = uses, defs = defs }
									 rf.instructions[ai] = info
									for _, r in ipairs(uses) do
										if not state.def[r] then addSet(state.use, r) end
									end
									for _, r in ipairs(defs) do
										state.def[r] = true
										local defKey = tostring(ai) .. ":" .. tostring(r)
										local byReg = definitionsByRegister[r] or {}
										byReg[#byReg + 1] = defKey
										definitionsByRegister[r] = byReg
										state.gen[r] = defKey
										rf.definitionInfo[defKey] = { action = ai, register = r }
										rf.definitions[ai] = rf.definitions[ai] or {}
										rf.definitions[ai][#rf.definitions[ai] + 1] = defKey
									end
								end
							end
							for blockId, state in ipairs(rf.blocks) do
								for r in pairs(state.def) do
									local allDefs = definitionsByRegister[r] or {}
									for _, defKey in ipairs(allDefs) do
										if defKey ~= state.gen[r] then state.kill[defKey] = true end
									end
								end
							end
							local liveChanged = true
							while liveChanged do
								liveChanged = false
								for blockId = #cfg.blocks, 1, -1 do
									local state = rf.blocks[blockId]
									local outSet, inSet = {}, {}
									for _, edge in ipairs(cfg.successors[blockId]) do
										for r in pairs(rf.blocks[edge.to].liveIn) do outSet[r] = true end
									end
									for r in pairs(state.use) do inSet[r] = true end
									for r in pairs(outSet) do if not state.def[r] then inSet[r] = true end end
									local changed = false
									for r in pairs(state.liveOut) do if not outSet[r] then changed = true end end
									for r in pairs(outSet) do if not state.liveOut[r] then changed = true end end
									for r in pairs(state.liveIn) do if not inSet[r] then changed = true end end
									for r in pairs(inSet) do if not state.liveIn[r] then changed = true end end
									if changed then state.liveIn, state.liveOut = inSet, outSet; liveChanged = true end
								end
							end
							-- Reaching definitions: union predecessor OUT sets, then apply block GEN/KILL.
							local reachChanged = true
							while reachChanged do
								reachChanged = false
								for blockId = 1, #cfg.blocks do
									local state = rf.blocks[blockId]
									local inSet = {}
									for _, pred in ipairs(cfg.predecessors[blockId]) do
										for defAi in pairs(rf.blocks[pred].outDefs) do inSet[defAi] = true end
									end
									local outSet = {}
									for defAi in pairs(inSet) do if not state.kill[defAi] then outSet[defAi] = true end end
									for _, defKey in pairs(state.gen) do outSet[defKey] = true end
									local changed = false
									for defAi in pairs(state.inDefs) do if not inSet[defAi] then changed = true end end
									for defAi in pairs(inSet) do if not state.inDefs[defAi] then changed = true end end
									for defAi in pairs(state.outDefs) do if not outSet[defAi] then changed = true end end
									for defAi in pairs(outSet) do if not state.outDefs[defAi] then changed = true end end
									if changed then state.inDefs, state.outDefs = inSet, outSet; reachChanged = true end
								end
							end
							for blockId, block in ipairs(cfg.blocks) do
								local defsAtEntry = {}
								for defKey in pairs(rf.blocks[blockId].inDefs) do
									local defInfo = rf.definitionInfo[defKey]
									if defInfo then
										local r = defInfo.register
										defsAtEntry[r] = defsAtEntry[r] or {}
										defsAtEntry[r][defKey] = true
									end
								end
								for r, incoming in pairs(defsAtEntry) do
									local count = 0
									for _ in pairs(incoming) do count += 1 end
									if count > 1 then rf.phiCandidates[#rf.phiCandidates + 1] = { block = blockId, register = r, incoming = incoming } end
								end
								local reaching = {}
								for defKey in pairs(rf.blocks[blockId].inDefs) do
									local defInfo = rf.definitionInfo[defKey]
									if defInfo then reaching[defInfo.register] = reaching[defInfo.register] or {}; reaching[defInfo.register][defKey] = true end
								end
								for ai = block.start, block.finish do
									local info = rf.instructions[ai]
									for _, r in ipairs(info.uses) do
										local found = false
										for defKey in pairs(reaching[r] or {}) do
											found = true
											local chain = rf.usesByDefinition[defKey] or {}
											chain[#chain + 1] = { action = ai, register = r }
											 rf.usesByDefinition[defKey] = chain
										end
										if not found then
											rf.uninitializedUses[#rf.uninitializedUses + 1] = {
												action = ai,
												register = r,
												entryValue = type(r) == "number" and r < numParams,
											}
										end
									end
									for _, r in ipairs(info.defs) do
										local byReg = reaching[r] or {}
										for defAi in pairs(byReg) do byReg[defAi] = nil end
										byReg[tostring(ai) .. ":" .. tostring(r)] = true
										 reaching[r] = byReg
									end
								end
							end
							return rf
						end
						cfg.registerFlow = buildRegisterDataFlow()
						local function isChainedRedefine(opName, ur2, ed2, defR, priorAct)
							local srcs = getSourceRegisters(opName, ur2, ed2)
							for k = 1, #srcs do
								if srcs[k] == defR then
									return true
								end
							end
							if priorAct and priorAct.opCode and priorAct.opCode.name == "NAMECALL" then
								if priorAct.usedRegisters and priorAct.usedRegisters[1] == defR then
									return true
								end
							end
							return false
						end
						local SELF_UPDATE_OPS = {
							ADD = true,
							SUB = true,
							MUL = true,
							DIV = true,
							MOD = true,
							POW = true,
							ADDK = true,
							SUBK = true,
							MULK = true,
							DIVK = true,
							MODK = true,
							POWK = true,
							AND = true,
							OR = true,
							ANDK = true,
							ORK = true,
						}
						local function isSelfUpdate(op, ur)
							if not SELF_UPDATE_OPS[op] or not ur or ur[1] == nil then
								return false
							end
							for k = 2, #ur do
								if ur[k] == ur[1] then
									return true
								end
							end
							return false
						end
						local regGeneration = {}
						local regGenTimeline = {}
						local function ensureRegTimeline(r)
							if not regGenTimeline[r] then
								regGenTimeline[r] = {}
								regGeneration[r] = 0
							end
						end
						for ai, act in ipairs(actions) do
							local actOpn = act.opCode and act.opCode.name
							if actOpn then
								local aur, aed = act.usedRegisters, act.extraData
								local srcs = getSourceRegisters(actOpn, aur, aed)
								for k = 1, #srcs do
									local r = srcs[k]
									ensureRegTimeline(r)
									local g = regGeneration[r]
									local tl = regGenTimeline[r]
									if tl[#tl] and tl[#tl].gen == g then
										tl[#tl].endIdx = ai
									end
								end
								local defs = getDefinedRegisters(actOpn, aur, aed)
								if isSelfUpdate(actOpn, aur) then
									defs = {}
								end
								for k = 1, #defs do
									local r = defs[k]
									ensureRegTimeline(r)
									local tl = regGenTimeline[r]
									if tl[#tl] then
										tl[#tl].endIdx = math.max(tl[#tl].endIdx or ai, ai - 1)
									end
									regGeneration[r] += 1
									tl[#tl + 1] = { gen = regGeneration[r], startIdx = ai, endIdx = ai, defAi = ai }
								end
							end
						end
						local regNeedsSuffix = {}
						for r, tl in pairs(regGenTimeline) do
							if #tl > 1 then
								regNeedsSuffix[r] = true
							end
						end
						local function regGenAt(r, instrIdx)
							local tl = regGenTimeline[r]
							if not tl then
								return 0
							end
							local best = 0
							for k = 1, #tl do
								local entry = tl[k]
								if entry.startIdx <= instrIdx then
									best = entry.gen
								else
									break
								end
							end
							return best
						end
						local function constStr(idx)
							local c = consts[idx + 1]
							if c and type(c.value) == "string" then
								return c.value
							end
							return nil
						end
						local function findRecentStringLiteral(r, beforeAi)
							for j = beforeAi - 1, math.max(1, beforeAi - 6), -1 do
								local a = actions[j]
								if not a or not a.opCode then
									continue
								end
								local an = a.opCode.name
								local au = a.usedRegisters
								if au and au[1] == r then
									if an == "LOADK" then
										return constStr(a.extraData[1])
									end
									return nil
								end
							end
							return nil
						end
						local SERVICE_LIKE_METHODS = { GetService = true }
						local CHILD_LOOKUP_METHODS = {
							WaitForChild = true,
							FindFirstChild = true,
							FindFirstChildOfClass = true,
							FindFirstChildWhichIsA = true,
						}
						local KNOWN_GLOBAL_NAMES = { game = true, workspace = true, script = true, shared = true }
						local function sanitizeName(s)
							if not s or s == "" then
								return nil
							end
							if not s:match("^[%a_][%w_]*$") then
								return nil
							end
							return s
						end
						local regInferredName = {}
						local regInferredGlobal = {}
						for r, tl in pairs(regGenTimeline) do
							for _, entry in ipairs(tl) do
								local defAi = entry.defAi
								local act = actions[defAi]
								if act and act.opCode then
									local opn2 = act.opCode.name
									local ed2 = act.extraData
									local name = nil
									local isGlobalValue = false
									if opn2 == "CALL" then
										local prevAct = actions[defAi - 1]
										if prevAct and prevAct.opCode and prevAct.opCode.name == "NAMECALL" then
											local method = constStr(prevAct.extraData[2])
											if
												method
												and (SERVICE_LIKE_METHODS[method] or CHILD_LOOKUP_METHODS[method])
											then
												local argReg = act.usedRegisters[1] + 1
												local lit = findRecentStringLiteral(argReg, defAi)
												name = sanitizeName(lit)
											end
										end
									elseif opn2 == "GETGLOBAL" then
										-- GETGLOBAL always denotes an environment lookup, not a local.
										-- Preserve every valid global identifier (not just Roblox roots).
										local gname = constStr(ed2[1])
										name = sanitizeName(gname)
										isGlobalValue = name ~= nil
									elseif opn2 == "GETIMPORT" then
										local gname = constStr(ed2[1])
										if gname and KNOWN_GLOBAL_NAMES[gname] == true then
											name = gname
											isGlobalValue = true
										end
									end
									if name then
										local key = r .. ":" .. entry.gen
										regInferredName[key] = name
										if isGlobalValue then
											regInferredGlobal[key] = true
										end
									end
								end
							end
						end
						-- Deconflict inferred locals only when their register generations
						-- have overlapping live intervals. A global "seen name" set is
						-- incorrect: unrelated locals lose useful names, and pairs() makes
						-- the winner nondeterministic across runs.
						do
							local candidates = {}
							for r, tl in pairs(regGenTimeline) do
								for _, entry in ipairs(tl) do
									local key = r .. ":" .. entry.gen
									local nm = regInferredName[key]
									if nm and not regInferredGlobal[key] then
										candidates[#candidates + 1] = {
											key = key,
											name = nm,
											startIdx = entry.startIdx or 1,
											endIdx = entry.endIdx or entry.startIdx or 1,
											register = r,
											generation = entry.gen,
										}
									end
								end
							end
							table.sort(candidates, function(a, b)
								if a.startIdx ~= b.startIdx then return a.startIdx < b.startIdx end
								if a.register ~= b.register then return a.register < b.register end
								return a.generation < b.generation
							end)
							local acceptedByName = {}
							for _, candidate in ipairs(candidates) do
								local accepted = acceptedByName[candidate.name] or {}
								local suffix = 1
								for _, prior in ipairs(accepted) do
									local overlaps = candidate.startIdx <= prior.endIdx
										and prior.startIdx <= candidate.endIdx
									if overlaps then suffix += 1 end
								end
								if suffix > 1 then
									regInferredName[candidate.key] = candidate.name .. "_" .. suffix
								end
								accepted[#accepted + 1] = candidate
								acceptedByName[candidate.name] = accepted
							end
						end
						local regNameCache = {}
						local function fmtReg(r, instrIdx)
							if r == nil then
								return "v?"
							end
							local safeNumParams = numParams or 0
							-- Named closure bindings outrank synthetic debug-local names.
							if instrIdx then
								local inferred = regInferredName[r .. ":" .. regGenAt(r, instrIdx)]
								if inferred then return inferred end
							end
							-- Prefer active debug-local names for parameters and locals alike.
							-- The previous ordering returned synthetic pN names before consulting
							-- debug info, and used action indexes as if they were bytecode PCs.
							if instrIdx and proto.debugLocals then
								local cached = regNameCache[instrIdx]
								if not cached then
									cached = buildRegNames(instrIdx)
									regNameCache[instrIdx] = cached
								end
								if cached[r] and cached[r] ~= "" then
									return cached[r]
								end
							end
							local pr = r + 1
							if pr < safeNumParams + 1 then
								return "p" .. tostring((totalParameters - safeNumParams) + pr)
							end
							if instrIdx then
								local g = regGenAt(r, instrIdx)
								local inferred = regInferredName[r .. ":" .. g]
								if inferred then
									return inferred
								end
							end
							local baseName = "v" .. tostring(r - safeNumParams)
							if instrIdx and regNeedsSuffix[r] then
								local g = regGenAt(r, instrIdx)
								if g > 1 then baseName ..= "_" .. g end
							end
							-- Never let a synthetic child-register temporary reuse the
							-- spelling of a captured parent local: that would shadow the
							-- upvalue and turn GETUPVAL/SETUPVAL into a self-assignment.
							if proto._captureNames then
								for _, capturedName in pairs(proto._captureNames) do
									if capturedName == baseName then
										baseName ..= "_local"
										break
									end
								end
							end
							return baseName
						end
						local function paramName(j)
							if proto.debugLocals then
								for _, dl in ipairs(proto.debugLocals) do
									if dl.startPC == 0 and dl.register == j - 1 then
										return dl.name
									end
								end
							end
							return "p" .. (totalParameters + j)
						end
						local function fmtConst(k)
							if not k then
								return "nil"
							end
							if k.type == LuauBytecodeTag.LBC_CONSTANT_VECTOR then
								return tostring(k.value)
							end
							if k.value == nil then
								return "nil"
							end
							if type(tonumber(k.value)) == "number" then
								local prec = tostring(7 or 14)
								return tostring(tonumber(string.format("%0." .. prec .. "f", k.value)))
							end
							return toEscapedString(k.value)
						end
						local function fmtProto(p)
							local body = ""
							local nativePrefix = ""
							if p.flags and p.flags.native then
								if p.flags.cold and false then
									nativePrefix ..= string.format(
										Strings.DECOMPILER_REMARK,
										"This function is marked cold and is not compiled natively"
									)
								end
								nativePrefix ..= "@native "
							end
							if p.name then
								body = nativePrefix .. "local function " .. p.name
							else
								body = nativePrefix .. "function"
							end
							body ..= "("
							for j = 1, p.numParams do
								local pb = paramName(j)
								if p.hasTypeInfo and true and p.typedParams and p.typedParams[j] then
									pb ..= ": " .. Luau:GetBaseTypeString(p.typedParams[j], true)
								end
								if j ~= p.numParams then
									pb ..= ", "
								end
								body ..= pb
							end
							if p.isVarArg then
								body ..= (p.numParams > 0) and ", ..." or "..."
							end
							body ..= ")"
							if false then
								body ..= "-- proto pool id: " .. tostring(p.id or "?") .. "\n"
								body ..= "-- num upvalues: " .. tostring(p.numUpvalues or "?") .. "\n"
								body ..= "-- num inner protos: " .. (p.sizeInnerProtos or 0) .. "\n"
								body ..= "-- size instructions: " .. (p.sizeInstructions or 0) .. "\n"
								body ..= "-- size constants: " .. (p.sizeConstants or 0) .. "\n"
								body ..= "-- lineinfo gap: " .. (p.lineInfoSize or "n/a") .. "\n"
								body ..= "-- max stack size: " .. tostring(p.maxStackSize or "?") .. "\n"
								body ..= "-- is typed: " .. tostring(p.hasTypeInfo) .. "\n"
							end
							return body
						end
						local function canonicalFunctionName(name)
							if type(name) ~= "string" or name == "" then
								return name
							end
							local base = name:match("^(.-)_%d+$")
							if base and base ~= "" then
								return base
							end
							return name
						end
						local function writeProto(reg, p, captureInstrIdx)
							local emittedName = canonicalFunctionName(p.name)
							-- Bind the closure destination before resolving captures so a
							-- recursive function's self-upvalue resolves to its lexical name.
							if p.name then
								local gen = regGenAt(reg, captureInstrIdx or 1)
								regInferredName[reg .. ":" .. gen] = emittedName
							end
							p._captureNames = p._captureNames or {}
							if p.captures then
								for capIndex, source in pairs(p.captures) do
									if type(source) == "number" then
										local parentName = fmtReg(source, captureInstrIdx or 1)
										if parentName and parentName ~= "v?" then
											p._captureNames[capIndex] = parentName
										end
									end
								end
							end
							local body
							if p.name and emittedName ~= p.name then
								body =
									fmtProto(p):gsub("local function " .. p.name, "local function " .. emittedName, 1)
							else
								body = fmtProto(p)
							end
							if p.name then
								-- A named Luau closure is already represented by its lexical
								-- local function declaration. Associate its destination register
								-- with that name so recursive and subsequent calls use the binding.
								emit("" .. body)
								writeActions(registerActions[p.id])
								emit("end")
							else
								emit(fmtReg(reg, captureInstrIdx) .. " = " .. body)
								writeActions(registerActions[p.id])
								emit("end")
							end
						end
						local CLEAN_SUPPRESS = {
							CLOSEUPVALS = true,
							PREPVARARGS = true,
							COVERAGE = true,
							CAPTURE = true,
							FASTCALL = true,
							FASTCALL1 = true,
							FASTCALL2 = true,
							FASTCALL2K = true,
							FASTCALL3 = true,
							JUMPX = true,
							NOP = true,
							JUMPBACK = true,
							NAMECALLUDATA = true,
							NAMECALL = true,
						}
						for i, action in ipairs(actions) do
							-- A jump target can land on the hidden opcode marker of an
							-- AUX-bearing instruction. Close/open structured branches before
							-- suppressing that marker, otherwise an else may be emitted as end.
							handleJumps(i)
							if action.hide then
								continue
							end
							local ur = action.usedRegisters
							local ed = action.extraData
							local oci = action.opCode
							if not oci then
								continue
							end
							local opn = oci.name
							if loopEnds[i] then
								if loopEnds[i] == "while" then
									indentLevel = math.max(0, indentLevel - 1)
									emit(ind() .. "end")
								end
								continue
							end
							if true and CLEAN_SUPPRESS[opn] then
								continue
							end
							if true and opn == "RETURN" then
								local b = ed and ed[1] or 0
								if b == 1 then
									continue
								end
							end
							if
								true
								and opn == "MOVE"
								and i > 1
								and actions[i - 1]
								and (
									actions[i - 1].opCode.name == "NEWCLOSURE"
									or actions[i - 1].opCode.name == "DUPCLOSURE"
								)
							then
								continue
							end
							local function R(r)
								local loopVar = numericLoopVars[r] or genericLoopVars[r]
								if loopVar and i >= loopVar.first and i <= loopVar.last then
									return loopVar.name
								end
								return fmtReg(r, i)
							end
							local function Rpre(r)
								return fmtReg(r, i - 1)
							end
							local function Rsrc(r)
								if not r then
									return "v?"
								end
								local defs = {}
								if
									opn == "MOVE"
									or opn == "GETTABLE"
									or opn == "GETTABLEKS"
									or opn == "GETTABLEN"
									or opn == "NOT"
									or opn == "MINUS"
									or opn == "LENGTH"
									or opn == "ADD"
									or opn == "SUB"
									or opn == "MUL"
									or opn == "DIV"
									or opn == "MOD"
									or opn == "POW"
									or opn == "AND"
									or opn == "OR"
									or opn == "CONCAT"
									or opn == "ADDK"
									or opn == "SUBK"
									or opn == "MULK"
									or opn == "DIVK"
									or opn == "MODK"
									or opn == "POWK"
									or opn == "ANDK"
									or opn == "ORK"
									or opn == "SUBRK"
									or opn == "DIVRK"
									or opn == "IDIV"
									or opn == "IDIVK"
									or opn == "GETUDATAKS"
									or opn == "NEWCLASSMEMBER"
								then
									defs = ur
								end
								if defs and defs[1] == r then
									return Rpre(r)
								end
								return R(r)
							end
							local function jumpTakenCondition()
								local a, b = ur[1], ur[2]
								if opn == "JUMPIF" then
									return R(a)
								end
								if opn == "JUMPIFNOT" then
									return "not " .. R(a)
								end
								local ops = {
									JUMPIFEQ = "==",
									JUMPIFNOTEQ = "~=",
									JUMPIFLT = "<",
									JUMPIFLE = "<=",
									JUMPIFNOTLT = ">=",
									JUMPIFNOTLE = ">",
								}
								return R(a) .. " " .. (ops[opn] or "==") .. " " .. R(b)
							end

							if loopStarts[i] then
								emit(ind() .. (loopStarts[i] == "repeat" and "repeat" or "while true do"))
								indentLevel += 1
							end
							if loopTests[i] then
								if loopTests[i] == "repeat" then
									indentLevel = math.max(0, indentLevel - 1)
									emit(ind() .. "until " .. jumpTakenCondition())
								else
									emit(ind() .. "if " .. jumpTakenCondition() .. " then break end")
								end
								continue
							end
							if loopEnds[i] then
								if loopEnds[i] == "while" then
									indentLevel = math.max(0, indentLevel - 1)
									emit(ind() .. "end")
								end
								continue
							end
							if not true then
								if false then
									emitRaw("[" .. padLeft(i, "0", 3) .. "] ")
								end
								if false and lineInfo and lineInfo[i] then
									emitRaw(":" .. padLeft(lineInfo[i], "0", 3) .. ":")
								end
								if false then
									emitRaw(padRight(opn, " ", 15))
								end
							end
							if opn == "LOADNIL" then
								emit(ind() .. R(ur[1]) .. " = nil")
							elseif opn == "LOADB" then
								local skipCount = ed[2] or 0
								local statement = ind() .. R(ur[1]) .. " = " .. toEscapedString(toBoolean(ed[1]))
								if skipCount ~= 0 then
									-- Keep bytecode skip metadata as a trailing comment. Emitting it
									-- with emitRaw() placed it after the line break, so the next
									-- emitted token could become invalid source such as "+1end".
									statement ..= " -- LOADB skip " .. tostring(skipCount)
								end
								emit(statement)
							elseif opn == "LOADN" then
								emit(ind() .. R(ur[1]) .. " = " .. ed[1])
							elseif opn == "LOADK" then
								emit(ind() .. R(ur[1]) .. " = " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "MOVE" then
								emit(ind() .. R(ur[1]) .. " = " .. Rsrc(ur[2]))
							elseif opn == "GETGLOBAL" then
								local gk = tostring(consts[ed[1] + 1] and consts[ed[1] + 1].value or "")
								if true and isValidGlobal(gk) then
									table.insert(usedGlobals, gk)
									usedGlobalsSet[gk] = true
								end
								if R(ur[1]) ~= gk then
									emit(ind() .. R(ur[1]) .. " = " .. gk)
								end
							elseif opn == "SETGLOBAL" then
								local gk = tostring(consts[ed[1] + 1] and consts[ed[1] + 1].value or "")
								if true and isValidGlobal(gk) then
									table.insert(usedGlobals, gk)
									usedGlobalsSet[gk] = true
								end
								emit(ind() .. gk .. " = " .. R(ur[1]))
							elseif opn == "GETUPVAL" then
								emit(ind() .. R(ur[1]) .. " = " .. fmtUpv(ed[1]))
							elseif opn == "SETUPVAL" then
								emit(ind() .. fmtUpv(ed[1]) .. " = " .. R(ur[1]))
							elseif opn == "CLOSEUPVALS" then
								emit(ind() .. "-- clear captures from back until: " .. ur[1])
							elseif opn == "GETIMPORT" then
								local imp = tostring(consts[ed[1] + 1] and consts[ed[1] + 1].value or "")
								local totalIdx = bit32.rshift(ed[2] or 0, 30)
								if totalIdx == 1 and true and isValidGlobal(imp) then
									table.insert(usedGlobals, imp)
									usedGlobalsSet[imp] = true
								end
								if R(ur[1]) ~= imp then
									emit(ind() .. R(ur[1]) .. " = " .. imp)
								end
							elseif opn == "GETTABLE" then
								emit(ind() .. R(ur[1]) .. " = " .. Rsrc(ur[2]) .. "[" .. Rsrc(ur[3]) .. "]")
							elseif opn == "SETTABLE" then
								emit(ind() .. R(ur[2]) .. "[" .. R(ur[3]) .. "] = " .. R(ur[1]))
							elseif opn == "GETTABLEKS" then
								local key = consts[ed[2] + 1] and consts[ed[2] + 1].value
								emit(ind() .. R(ur[1]) .. " = " .. Rsrc(ur[2]) .. formatIndexString(key))
							elseif opn == "SETTABLEKS" then
								local key = consts[ed[2] + 1] and consts[ed[2] + 1].value
								emit(ind() .. R(ur[2]) .. formatIndexString(key) .. " = " .. R(ur[1]))
							elseif opn == "GETTABLEN" then
								emit(ind() .. R(ur[1]) .. " = " .. Rsrc(ur[2]) .. "[" .. (ed[1] + 1) .. "]")
							elseif opn == "SETTABLEN" then
								emit(ind() .. R(ur[2]) .. "[" .. (ed[1] + 1) .. "] = " .. R(ur[1]))
							elseif opn == "NEWCLOSURE" then
								local p2 = inner[ed[1] + 1]
								if p2 then
									writeProto(ur[1], p2, i)
								end
							elseif opn == "DUPCLOSURE" then
								local c = consts[ed[1] + 1]
								if c then
									local p2 = protoTable[c.value - 1]
									if p2 then
										writeProto(ur[1], p2, i)
									end
								end
							elseif opn == "NAMECALL" then
								local method = tostring(consts[ed[2] + 1] and consts[ed[2] + 1].value or "")
								emit(ind() .. "-- :" .. method)
							elseif opn == "CALL" then
								local baseR = ur[1]
								local nArgs = (ed[1] or 1) - 1
								local resultCount = ed[2] or 1
								local isMultiReturn = resultCount == 0
								local nRes = isMultiReturn and -1 or (resultCount - 1)
								local nmMethod = ""
								local argOff = 0
								local prev = actions[i - 1]
								if prev and prev.opCode and prev.opCode.name == "NAMECALL" then
									nmMethod = ":"
										.. tostring(
											consts[prev.extraData[2] + 1] and consts[prev.extraData[2] + 1].value or ""
										)
									nArgs -= 1
									argOff += 1
								end
								local callBody = ""
								if isMultiReturn then
									callBody = R(baseR) .. " = "
								elseif nRes > 0 then
									local rb = ""
									for k = 1, nRes do
										rb ..= R(baseR + k - 1)
										if k ~= nRes then
											rb ..= ", "
										end
									end
									callBody = rb .. " = "
								end
								local receiverR = baseR
								if prev and prev.opCode and prev.opCode.name == "NAMECALL" then
									if prev.usedRegisters and prev.usedRegisters[2] ~= nil then
										receiverR = prev.usedRegisters[2]
									end
								end
								-- NAMECALL writes its callable/self pair into A/A+1.  When A aliases
								-- the receiver register, Rpre() at the CALL site sees the
								-- post-NAMECALL generation and invents a synthetic local.
								-- NAMECALL has an AUX marker before it, so i-2 is pre-NAMECALL.
								local receiverExpr = fmtReg(receiverR, i - 2)
								callBody ..= receiverExpr .. nmMethod .. "("
								if
									nArgs == -1
									and openCallTail
									and openCallTail.producer == prevIndex
									and openCallTail.base >= baseR + 1 + argOff
								then
									local parts = {}
									for r = baseR + 1 + argOff, openCallTail.base - 1 do
										parts[#parts + 1] = Rpre(r)
									end
									parts[#parts + 1] = openCallTail.expression
									callBody ..= table.concat(parts, ", ")
									openCallTail = nil
								elseif nArgs == -1 then
									local topReg
									for back = i - 1, math.max(1, i - 12), -1 do
										local producer = actions[back]
										local producerName = producer and producer.opCode and producer.opCode.name
										if producerName == "CALL" or producerName == "CALLFB" then
											local pr = producer.usedRegisters and producer.usedRegisters[1]
											local rc = producer.extraData and producer.extraData[2]
											if pr ~= nil and rc and rc > 1 then
												topReg = pr + rc - 2
											end
											break
										elseif producerName == "GETVARARGS" then
											break
										elseif
											producerName == "JUMP"
											or producerName == "JUMPBACK"
											or producerName == "RETURN"
										then
											break
										end
									end
									local firstArg = baseR + 1 + argOff
									if topReg and topReg >= firstArg then
										local parts = {}
										for r = firstArg, topReg do
											parts[#parts + 1] = Rpre(r)
										end
										callBody ..= table.concat(parts, ", ")
									else
										callBody ..= "..."
									end
								elseif nArgs > 0 then
									local ab = ""
									for k = 1, nArgs do
										ab ..= Rpre(baseR + k + argOff)
										if k ~= nArgs then
											ab ..= ", "
										end
									end
									callBody ..= ab
								end
								callBody ..= ")"
								local nextIndex = nextVisibleAction(i)
								local nextAction = nextIndex and actions[nextIndex]
								local nextName = nextAction and nextAction.opCode and nextAction.opCode.name
								local nextIsOpenCall = nextName == "CALL" and nextAction.extraData and nextAction.extraData[1] == 0
								local nextIsOpenReturn = nextName == "RETURN" and nextAction.extraData and nextAction.extraData[1] == 0
								local nextIsGenericPrep = nextName == "FORGPREP" or nextName == "FORGPREP_INEXT" or nextName == "FORGPREP_NEXT"
								if nRes > 0 and nextIsGenericPrep then
									local rhs = callBody:match("=%s*(.*)$")
									iteratorCalls[baseR] = { producer = i, base = baseR, expression = rhs or "..." }
								elseif isMultiReturn and (nextIsOpenCall or nextIsOpenReturn) then
									openCallTail = {
										producer = i,
										base = baseR,
										expression = callBody:sub(#(R(baseR) .. " = ") + 1),
									}
								else
									emit(ind() .. callBody)
								end
							elseif opn == "RETURN" then
								local baseR = ur[1]
								local returnCount = ed[1] or 1 -- Luau B: count including the implicit +1
								local rb = ""
								if returnCount == 0 then
									-- Open returns forward the immediately preceding open producer.
									-- A CALL with C=0 returns its full result tuple; GETVARARGS
									-- with B=0 forwards the vararg tuple. Do not append a fabricated ...
									local prevIndex = previousVisibleAction(i)
									local prev = prevIndex and actions[prevIndex]
									local prevName = prev and prev.opCode and prev.opCode.name
									if openCallTail and openCallTail.producer == prevIndex then
										rb = " " .. openCallTail.expression
										openCallTail = nil
									elseif prevName == "GETVARARGS" and prev.extraData and prev.extraData[1] == 0 then
										rb = " ..."
									elseif prevName == "CALL" or prevName == "CALLFB" then
										-- Fallback for a call whose open result was not retained.
										local callee = prev.usedRegisters and prev.usedRegisters[1]
										rb = " " .. (callee and R(callee) or R(baseR))
									else
										rb = " " .. R(baseR)
									end
								elseif returnCount > 1 then
									rb = " "
									for k = 0, returnCount - 2 do
										rb ..= R(baseR + k)
										if k ~= returnCount - 2 then rb ..= ", " end
									end
								end
								emit(ind() .. "return" .. rb)
							elseif opn == "JUMP" then
								if not elseJumpIndices[i] then
									emit("-- jump to #" .. jumpTarget(i, ed[1]))
								end
							elseif opn == "JUMPBACK" then
								emit(ind() .. "-- jump back to #" .. jumpTarget(i, ed[1]))
							elseif opn == "JUMPIF" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if not " .. R(ur[1]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOT" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFEQ" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " ~= " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFLE" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " > " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFLT" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " >= " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOTEQ" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " == " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOTLE" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " <= " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOTLT" then
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " < " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "ADD" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " + " .. Rsrc(ur[3]))
							elseif opn == "SUB" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " - " .. Rsrc(ur[3]))
							elseif opn == "MUL" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " * " .. Rsrc(ur[3]))
							elseif opn == "DIV" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " / " .. Rsrc(ur[3]))
							elseif opn == "MOD" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " % " .. Rsrc(ur[3]))
							elseif opn == "POW" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " ^ " .. Rsrc(ur[3]))
							elseif opn == "ADDK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " + " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "SUBK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " - " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "MULK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " * " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "DIVK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " / " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "MODK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " % " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "POWK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " ^ " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "AND" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " and " .. Rsrc(ur[3]))
							elseif opn == "OR" then
								emit(R(ur[1]) .. " = " .. Rsrc(ur[2]) .. " or " .. Rsrc(ur[3]))
							elseif opn == "ANDK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " and " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "ORK" then
								emit(R(ur[1]) .. " = " .. R(ur[2]) .. " or " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "CONCAT" then
								local tgt = table.remove(ur, 1)
								local cb = ""
								for k, r in ipairs(ur) do
									cb ..= fmtReg(r, i)
									if k ~= #ur then
										cb ..= " .. "
									end
								end
								emit(ind() .. R(tgt) .. " = " .. cb)
							elseif opn == "NOT" then
								emit(ind() .. R(ur[1]) .. " = not " .. Rsrc(ur[2]))
							elseif opn == "MINUS" then
								emit(ind() .. R(ur[1]) .. " = -" .. Rsrc(ur[2]))
							elseif opn == "LENGTH" then
								emit(ind() .. R(ur[1]) .. " = #" .. Rsrc(ur[2]))
							elseif opn == "NEWTABLE" then
								emit(R(ur[1]) .. " = {}")
								if false and ed[2] and ed[2] > 0 then
									emitRaw(" ")
								end
							elseif opn == "DUPTABLE" then
								emit(R(ur[1]) .. " = {}")
							elseif opn == "SETLIST" then
								local tgt = ur[1]
								local src = ur[2]
								local si = ed[1]
								local vc = ed[2]
								if vc == 0 then
									emit(R(tgt) .. "[" .. si .. "] = " .. R(src))
								else
									local prevNewTable = false
									for back = i - 1, math.max(1, i - 8), -1 do
										local pa = actions[back]
										if not pa or pa.hide then
											continue
										end
										if pa.opCode then
											if
												pa.opCode.name == "NEWTABLE"
												and pa.usedRegisters
												and pa.usedRegisters[1] == tgt
											then
												prevNewTable = true
											end
										end
										break
									end
									local tot2 = #ur - 1
									if prevNewTable and si == 1 and tot2 > 0 then
										local vals = {}
										for k = 1, tot2 do
											vals[k] = fmtReg(src + k - 1, i)
										end
										local tgtName = R(tgt)
										for rp = #resultParts, math.max(1, #resultParts - 10), -1 do
											if
												resultParts[rp] and resultParts[rp]:find(tgtName .. " = {}", 1, true)
											then
												if tot2 <= 4 then
													resultParts[rp] = tgtName
														.. " = { "
														.. table.concat(vals, ", ")
														.. " }"
												else
													local sep = ",\n\t"
													resultParts[rp] = tgtName
														.. " = {\n\t"
														.. table.concat(vals, sep)
														.. "\n}"
												end
												break
											end
										end
									else
										local cb = ""
										for k = 1, tot2 do
											cb ..= R(tgt) .. "[" .. (si + k - 1) .. "] = " .. R(src + k - 1)
											if k ~= tot2 then
												cb ..= "\n"
											end
										end
										emit(cb)
									end
								end
							elseif opn == "FORNPREP" then
								local loopEnd = flow.numeric[i] or (i + ed[1] + 1)
								local startExpr = fmtReg(ur[3], i - 1)
								local limitExpr = fmtReg(ur[1], i - 1)
								local stepExpr = fmtReg(ur[2], i - 1)
								local indexName = "i" .. tostring(i)
								numericLoopVars[ur[3]] = { name = indexName, first = i + 1, last = loopEnd - 1 }
								emit(
									"for "
										.. indexName
										.. " = "
										.. startExpr
										.. ", "
										.. limitExpr
										.. ", "
										.. stepExpr
										.. " do"
								)
							elseif opn == "FORNLOOP" then
								emit("end -- iterate + jump to #" .. jumpTarget(i, ed[1]))
							elseif opn == "FORGLOOP" then
								emit("end -- iterate + jump to #" .. jumpTarget(i, ed[1]))
							elseif opn == "FORGPREP_INEXT" or opn == "FORGPREP_NEXT" then
								local base = ur[1]
								local loopEnd = flow.generic[i] or (#actions + 1)
								local loopAction = actions[loopEnd]
								if not loopAction or not loopAction.opCode or loopAction.opCode.name ~= "FORGLOOP" then
									for j = i + 1, #actions do
										local candidate = actions[j]
										if candidate.opCode and candidate.opCode.name == "FORGLOOP"
											and candidate.extraData and candidate.extraData[3] == base then
											loopEnd = j
											loopAction = candidate
											break
										end
									end
								end
								local resultCount = loopAction and loopAction.extraData and bit32.band(loopAction.extraData[2] or 0, 0xFF) or 2
								local debugNames = buildRegNames(i + 1)
								local names = {}
								for k = 1, resultCount do
									local register = base + 2 + k
									local name = debugNames[register]
									if not name or name == "" then
										name = (k == 1 and "i" or (k == 2 and "v" or ("v" .. k))) .. tostring(i)
									end
									name = sanitizeName(name) or ((k == 1 and "i" or "v") .. tostring(i) .. "_" .. k)
									genericLoopVars[register] = { name = name, first = i + 1, last = loopEnd - 1 }
									names[k] = name
								end
								local iterator = opn == "FORGPREP_INEXT" and "ipairs" or "pairs"
								local pendingIterator = iteratorCalls[base]
								local iteratorExpression = pendingIterator and pendingIterator.expression or (iterator .. "(" .. R(base + 1) .. ")")
								iteratorCalls[base] = nil
								emit("for " .. table.concat(names, ", ") .. " in " .. iteratorExpression .. " do")
							elseif opn == "FORGPREP" then
								local ei = flow.generic[i] or jumpTarget(i, ed[1])
								local ea = actions[ei]
								local vb = ""
								if ea then
									for k, r in ipairs(ea.usedRegisters) do
										vb ..= fmtReg(r, i)
										if k ~= #ea.usedRegisters then vb ..= ", " end
									end
								end
								local base = ur[1]
								local pendingIterator = iteratorCalls[base]
								local iteratorExpression = pendingIterator and pendingIterator.expression or R(base)
								iteratorCalls[base] = nil
								emit("for " .. vb .. " in " .. iteratorExpression .. " do")
							elseif opn == "GETVARARGS" then
								local nextAction = actions[i + 1]
								if ed[1] == 0 and nextAction and nextAction.opCode and nextAction.opCode.name == "RETURN" and nextAction.extraData and nextAction.extraData[1] == 0 then
									continue
								end
								local vc2 = ed[1] - 1
								local rb = ""
								if vc2 == -1 then
									rb = R(ur[1])
								else
									for k = 1, vc2 do
										rb ..= R(ur[k])
										if k ~= vc2 then
											rb ..= ", "
										end
									end
								end
								emit(ind() .. rb .. " = ...")
							elseif opn == "PREPVARARGS" then
								emit(ind() .. "-- ... ; number of fixed args: " .. ed[1])
							elseif opn == "LOADKX" then
								emit(ind() .. R(ur[1]) .. " = " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "JUMPX" then
								emit(ind() .. "-- jump to #" .. jumpTarget(i, ed[1]))
							elseif opn == "COVERAGE" then
								emit(ind() .. "-- coverage (" .. ed[1] .. ")")
							elseif opn == "JUMPXEQKNIL" then
								local rev = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
								local sign = rev and "~=" or "=="
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " " .. sign .. " nil then -- goto #" .. ei)
							elseif opn == "JUMPXEQKB" then
								local val = tostring(toBoolean(bit32.band(ed[2] or 0, 1)))
								local rev = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
								local sign = rev and "~=" or "=="
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " " .. sign .. " " .. val .. " then -- goto #" .. ei)
							elseif opn == "JUMPXEQKN" or opn == "JUMPXEQKS" then
								local cidx = bit32.band(ed[2] or 0, 0xFFFFFF)
								local val = fmtConst(consts[cidx + 1])
								local rev = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
								local sign = rev and "~=" or "=="
								local ei = jumpTarget(i, ed[1])
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " " .. sign .. " " .. val .. " then -- goto #" .. ei)
							elseif opn == "CAPTURE" then
								emit(ind() .. "-- upvalue capture")
							elseif opn == "SUBRK" then
								emit(ind() .. R(ur[1]) .. " = " .. fmtConst(consts[ed[1] + 1]) .. " - " .. R(ur[2]))
							elseif opn == "DIVRK" then
								emit(ind() .. R(ur[1]) .. " = " .. fmtConst(consts[ed[1] + 1]) .. " / " .. R(ur[2]))
							elseif opn == "IDIV" then
								emit(ind() .. R(ur[1]) .. " = " .. R(ur[2]) .. " // " .. R(ur[3]))
							elseif opn == "IDIVK" then
								emit(ind() .. R(ur[1]) .. " = " .. R(ur[2]) .. " // " .. fmtConst(consts[ed[1] + 1]))
							elseif opn == "GETUDATAKS" then
								local key = consts[ed[2] + 1] and consts[ed[2] + 1].value
								emit(ind() .. R(ur[1]) .. " = " .. Rsrc(ur[2]) .. formatIndexString(key))
							elseif opn == "SETUDATAKS" then
								local key = consts[ed[2] + 1] and consts[ed[2] + 1].value
								emit(ind() .. R(ur[2]) .. formatIndexString(key) .. " = " .. R(ur[1]))
							elseif opn == "NAMECALLUDATA" then
								local method = tostring(consts[ed[2] + 1] and consts[ed[2] + 1].value or "")
								emit(ind() .. "-- :" .. method .. " (udata)")
							elseif opn == "NEWCLASSMEMBER" then
								local name = consts[(ed[1] or 0) + 1] and consts[(ed[1] or 0) + 1].value or "?"
								emit(ind() .. R(ur[1]) .. "." .. tostring(name) .. " = " .. R(ur[2]))
							elseif opn == "CALLFB" then
								local baseR = ur[1]
								local nArgs = (ed[1] or 1) - 1
								local nRes = (ed[2] or 1) - 1
								local previousNamecall
								for back = i - 1, math.max(1, i - 4), -1 do
									local candidate = actions[back]
									if candidate and not candidate.hide then
										if
											candidate.opCode
											and candidate.opCode.name == "NAMECALL"
											and candidate.usedRegisters
											and candidate.usedRegisters[1] == baseR
										then
											previousNamecall = candidate
										end
										break
									end
								end
								local callBody = ""
								if nRes == -1 then
									callBody = R(baseR) .. " = "
								elseif nRes > 0 then
									local results = {}
									for k = 0, nRes - 1 do
										results[#results + 1] = R(baseR + k)
									end
									callBody = table.concat(results, ", ") .. " = "
								end
								local firstArg = baseR + 1
								if previousNamecall then
									local methodIdx = previousNamecall.extraData and previousNamecall.extraData[2]
									local method = methodIdx and consts[methodIdx + 1] and consts[methodIdx + 1].value
									local receiver = previousNamecall.usedRegisters[2]
									callBody ..= Rpre(receiver) .. formatIndexString(method or "")
									local suffix = formatIndexString(method or "")
									if suffix:sub(1, 1) == "." then
										callBody = callBody:sub(1, #callBody - #suffix) .. ":" .. suffix:sub(2)
									end
									firstArg = baseR + 2
									nArgs -= 1
								else
									callBody ..= Rpre(baseR)
								end
								local args = {}
								if nArgs < 0 then
									args[1] = "..."
								else
									for k = 0, nArgs - 1 do
										args[#args + 1] = Rpre(firstArg + k)
									end
								end
								emit(ind() .. callBody .. "(" .. table.concat(args, ", ") .. ")")
							elseif opn == "CMPPROTO" then
								local ei = jumpTarget(i, ed[1] or 0)
								makeJump(ei)
								emit(
									"if not proto_match("
										.. R(ur[1])
										.. ", proto#"
										.. tostring(ed[2] or "?")
										.. ") then -- goto #"
										.. ei
								)
							elseif opn == "FASTCALL" then
								emit("-- FASTCALL; " .. Luau:GetBuiltinInfo(ed[1]) .. "()")
							elseif opn == "FASTCALL1" then
								emit("-- FASTCALL1; " .. Luau:GetBuiltinInfo(ed[1]) .. "(" .. R(ur[1]) .. ")")
							elseif opn == "FASTCALL2" then
								emit(
									"-- FASTCALL2; "
										.. Luau:GetBuiltinInfo(ed[1])
										.. "("
										.. R(ur[1])
										.. ", "
										.. R(ur[2])
										.. ")"
								)
							elseif opn == "FASTCALL2K" then
								emit(
									"-- FASTCALL2K; "
										.. Luau:GetBuiltinInfo(ed[1])
										.. "("
										.. R(ur[1])
										.. ", "
										.. fmtConst(consts[(ed[3] or 0) + 1])
										.. ")"
								)
							elseif opn == "FASTCALL3" then
								emit(
									"-- FASTCALL3; "
										.. Luau:GetBuiltinInfo(ed[1])
										.. "("
										.. R(ur[1])
										.. ", "
										.. R(ur[2])
										.. ", "
										.. R(ur[3])
										.. ")"
								)
							end
						end
					end
					writeActions(registerActions[mainProtoId])
					finalResult = processResult(table.concat(resultParts))
				else
					finalResult = processResult("-- one day..")
				end
				return finalResult
			end
			-- Semantic IR + deliberately conservative source backend.  This backend is
			-- opt-in (`Decompile(bytecode, { mode = "safe" })` / CLI `--safe`).  It
			-- emits source only when every instruction in the selected prototype is
			-- covered by the subset below; otherwise it returns an explicit failure
			-- instead of guessing and silently changing program behavior.
			local function decompileSafeSubset(mainProtoId, registerActions, protoTable)
				local protoActions = registerActions[mainProtoId]
				local proto = protoTable[mainProtoId]
				if not protoActions or not proto then
					return nil, "main prototype metadata is missing"
				end
				local actions = protoActions.actions or {}
				local constants = proto.constants or {}
				local ir = {
					protoId = mainProtoId,
					maxStackSize = proto.maxStackSize,
					numParams = proto.numParams,
					numUpvalues = proto.numUpvalues,
					isVarArg = proto.isVarArg,
					constants = constants,
					upvalues = proto.captures,
					children = proto.innerProtos,
					instructions = {}, blocks = {}, blockAt = {}, edges = {},
				}
				local actionToIR = {}
				local pcToIR = {}
				for actionIndex, action in ipairs(actions) do
					if not action.hide and action.opCode then
						local ins = {
							actionIndex = actionIndex,
							pc = action.bytecodePC or (actionIndex - 1),
							op = action.opCode.name,
							registers = table.clone(action.usedRegisters or {}),
							operands = table.clone(action.extraData or {}),
							line = proto.instructionLineInfo and proto.instructionLineInfo[action.bytecodePC or actionIndex] or nil,
							aux = nil,
						}
						if ins.op == "GETGLOBAL" or ins.op == "SETGLOBAL" then
							ins.aux = ins.operands[1]
						elseif ins.op == "GETIMPORT" then
							ins.aux = ins.operands[2]
						elseif ins.op == "NAMECALL" then
							ins.aux = ins.operands[2]
						elseif ins.op == "GETTABLEKS" or ins.op == "SETTABLEKS" then
							ins.aux = ins.operands[2]
						elseif ins.op == "NEWTABLE" or ins.op == "SETLIST" then
							ins.aux = ins.operands[2] or ins.operands[1]
						end
						-- Explicit register effects keep semantic reads/writes separate
						-- from the legacy mixed-purpose usedRegisters array.
						ins.reads, ins.writes = {}, {}
						local rr, ee = ins.registers, ins.operands
						local ra, rb, rc = rr[1], rr[2], rr[3]
						local function read(register) if type(register) == "number" then ins.reads[#ins.reads + 1] = register end end
						local function write(register) if type(register) == "number" then ins.writes[#ins.writes + 1] = register end end
						local function readRange(first, count) if type(first) == "number" and type(count) == "number" then for register = first, first + count - 1 do read(register) end end end
						if ins.op == "MOVE" then read(rb); write(ra)
						elseif ins.op == "SETGLOBAL" then read(ra)
						elseif ins.op == "GETGLOBAL" or ins.op == "GETIMPORT" or ins.op == "LOADNIL" or ins.op == "LOADB" or ins.op == "LOADN" or ins.op == "LOADK" or ins.op == "NEWTABLE" then write(ra)
						elseif ins.op == "GETTABLE" then read(rb); read(rc); write(ra)
						elseif ins.op == "GETTABLEKS" or ins.op == "GETTABLEN" then read(rb); write(ra)
						elseif ins.op == "SETTABLE" then read(ra); read(rb); read(rc)
						elseif ins.op == "SETTABLEKS" or ins.op == "SETTABLEN" then read(ra); read(rb)
						elseif ins.op == "NAMECALL" then read(rb); write(ra); if type(ra) == "number" then write(ra + 1) end
						elseif ins.op == "CALL" or ins.op == "CALLFB" then readRange(ra, (ee[1] or 1)); if (ee[2] or 1) > 1 then for register = ra, ra + ee[2] - 2 do write(register) end end
						elseif ins.op == "RETURN" then if (ee[1] or 0) > 1 then readRange(ra, ee[1] - 1) end
						elseif ins.op == "ADD" or ins.op == "SUB" or ins.op == "MUL" or ins.op == "DIV" or ins.op == "MOD" or ins.op == "POW" or ins.op == "IDIV" or ins.op == "AND" or ins.op == "OR" then read(rb); read(rc); write(ra)
						elseif ins.op == "ADDK" or ins.op == "SUBK" or ins.op == "MULK" or ins.op == "DIVK" or ins.op == "MODK" or ins.op == "POWK" or ins.op == "IDIVK" or ins.op == "ANDK" or ins.op == "ORK" then read(rb); write(ra)
						elseif ins.op == "SUBRK" or ins.op == "DIVRK" then read(rb); write(ra)
						elseif ins.op == "NOT" or ins.op == "MINUS" or ins.op == "LENGTH" then read(rb); write(ra)
						elseif ins.op == "CONCAT" then readRange(rb, rc - rb + 1); write(ra)
						end
						ins.action = action
						local index = #ir.instructions + 1
						ir.instructions[index] = ins
						ins.irIndex = index
						actionToIR[actionIndex] = index
						pcToIR[ins.pc] = index
					end
				end
				-- Build block boundaries and edges from original bytecode PCs.  This
				-- representation is retained even when the safe backend rejects branches.
				local leaders = { [1] = true }
				local branchOps = {
					JUMP = true, JUMPBACK = true, JUMPX = true,
					JUMPIF = true, JUMPIFNOT = true, JUMPIFEQ = true, JUMPIFLE = true,
					JUMPIFLT = true, JUMPIFNOTEQ = true, JUMPIFNOTLE = true, JUMPIFNOTLT = true,
					JUMPXEQKNIL = true, JUMPXEQKB = true, JUMPXEQKN = true, JUMPXEQKS = true,
					FORNPREP = true, FORNLOOP = true, FORGLOOP = true, FORGPREP = true,
					FORGPREP_INEXT = true, FORGPREP_NEXT = true,
				}
				for index, ins in ipairs(ir.instructions) do
					if branchOps[ins.op] then
						local delta = ins.operands[1]
						if type(delta) == "number" then
							local target = pcToIR[ins.pc + delta + 1]
							if target then leaders[target] = true; ins.target = target end
						end
						if index < #ir.instructions then leaders[index + 1] = true end
					elseif ins.op == "RETURN" and index < #ir.instructions then
						leaders[index + 1] = true
					end
				end
				local leaderList = {}
				for index in pairs(leaders) do leaderList[#leaderList + 1] = index end
				table.sort(leaderList)
				for blockIndex, first in ipairs(leaderList) do
					local block = { id = blockIndex, first = first, last = (leaderList[blockIndex + 1] or (#ir.instructions + 1)) - 1 }
					ir.blocks[blockIndex] = block
					for index = block.first, block.last do ir.blockAt[index] = blockIndex end
				end
				for blockIndex, block in ipairs(ir.blocks) do
					local last = ir.instructions[block.last]
					local nextBlock = ir.blocks[blockIndex + 1]
					if last and last.target and ir.blockAt[last.target] then
						ir.edges[#ir.edges + 1] = { from = blockIndex, to = ir.blockAt[last.target], kind = "taken" }
					end
					if nextBlock and (not last or (last.op ~= "JUMP" and last.op ~= "JUMPBACK" and last.op ~= "JUMPX" and last.op ~= "RETURN")) then
						ir.edges[#ir.edges + 1] = { from = blockIndex, to = nextBlock.id, kind = "fallthrough" }
					end
				end
				local function fail(ins, why)
					return nil, string.format("%s at bytecode PC %s (prototype %s)", why, tostring(ins and ins.pc or "?"), tostring(mainProtoId))
				end
				local function quote(value)
					return toEscapedString(tostring(value))
				end
				local function constant(index)
					local item = constants[(tonumber(index) or -1) + 1]
					if not item then return nil, "constant index out of range: " .. tostring(index) end
					local value = item.value
					if value == nil then return "nil" end
					if type(value) == "string" then return quote(value) end
					if type(value) == "boolean" then return value and "true" or "false" end
					if type(value) == "number" then
						if value ~= value or value == math.huge or value == -math.huge then
							return nil, "non-finite numeric constant is unsupported"
						end
						return string.format("%.17g", value)
					end
					return nil, "constant type " .. tostring(item.type) .. " is not supported by safe source mode"
				end
				local safeKeywords = {}
				for _, keyword in ipairs({
					"and", "break", "do", "else", "elseif", "end", "false", "for", "function",
					"if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
				}) do safeKeywords[keyword] = true end
				local function validIdentifierPath(path)
					if type(path) ~= "string" then return false end
					local first, rest = path:match("^([%a_][%w_]*)(.*)$")
					if not first or safeKeywords[first] then return false end
					while rest ~= "" do
						local segment, tail = rest:match("^%.([%a_][%w_]*)(.*)$")
						if not segment or safeKeywords[segment] then return false end
						rest = tail
					end
					return true
				end
				local function globalExpr(name)
					if type(name) ~= "string" or name == "" then return nil end
					if name:match("^[%a_][%w_]*$") and not safeKeywords[name] then return name end
					return "_G[" .. quote(name) .. "]"
				end
				local regs, lines = {}, {}
				local tempId = 0
				local function temp(code, hint)
					tempId += 1
					local name = "__zuka_" .. (hint or "v") .. tostring(tempId)
					lines[#lines + 1] = "local " .. name .. " = " .. code
					return { code = name, materialized = true }
				end
				local function getReg(register, ins)
					local value = regs[register]
					if not value then return nil, "read of uninitialized register R" .. tostring(register) .. " at PC " .. tostring(ins.pc) end
					return value
				end
				local function getCode(register, ins)
					local value, err = getReg(register, ins)
					if not value then return nil, err end
					return value.code
				end
				local function setValue(register, value)
					regs[register] = value
				end
				local function materialize(register, hint)
					local value = regs[register]
					if value and not value.materialized then regs[register] = temp(value.code, hint) end
				end
				local function setGlobalValue(register, code, ins)
					-- Keep the common GETGLOBAL -> NAMECALL receiver path symbolic so
					-- `game:GetService(...)` stays a global expression, not a synthetic
					-- local. Other global reads are captured at their bytecode point.
					local nextIns = ir.instructions[ins.irIndex + 1]
					if nextIns and nextIns.op == "NAMECALL" and nextIns.registers[2] == register then
						setValue(register, { code = code, global = true })
					else
						setValue(register, temp(code, "global"))
					end
				end
				local function keyExpr(key)
					if type(key) == "string" and key:match("^[%a_][%w_]*$") and not safeKeywords[key] then return "." .. key end
					return "[" .. quote(key) .. "]"
				end
				local supported = {
					NOP = true, BREAK = true, COVERAGE = true, NATIVECALL = true,
					LOADNIL = true, LOADB = true, LOADN = true, LOADK = true, MOVE = true,
					GETGLOBAL = true, SETGLOBAL = true, GETIMPORT = true,
					GETTABLE = true, SETTABLE = true, GETTABLEKS = true, SETTABLEKS = true,
					GETTABLEN = true, SETTABLEN = true, NEWTABLE = true,
					NAMECALL = true, CALL = true, RETURN = true,
					ADD = true, SUB = true, MUL = true, DIV = true, MOD = true, POW = true,
					ADDK = true, SUBK = true, MULK = true, DIVK = true, MODK = true, POWK = true,
					AND = true, OR = true, ANDK = true, ORK = true, CONCAT = true,
					NOT = true, MINUS = true, LENGTH = true, IDIV = true, IDIVK = true,
					SUBRK = true, DIVRK = true,
					FASTCALL = true, FASTCALL1 = true, FASTCALL2 = true, FASTCALL2K = true, FASTCALL3 = true,
					PREPVARARGS = true,
				}
				for _, ins in ipairs(ir.instructions) do
					if not supported[ins.op] then return fail(ins, "unsupported construct " .. tostring(ins.op)) end
					if branchOps[ins.op] then return fail(ins, "control-flow construct requires structuring and is not in the safe linear subset") end
				end
				if proto.isVarArg then
					return nil, "vararg prototype is not in the safe linear subset (prototype " .. tostring(mainProtoId) .. ")"
				end
				if (proto.numUpvalues or 0) > 0 then
					return nil, "prototype captures upvalues; closure semantics are not in the safe linear subset (prototype " .. tostring(mainProtoId) .. ")"
				end
				local binary = {
					ADD = "+", SUB = "-", MUL = "*", DIV = "/", MOD = "%", POW = "^",
					IDIV = "//", AND = "and", OR = "or",
				}
				local binaryK = {
					ADDK = "+", SUBK = "-", MULK = "*", DIVK = "/", MODK = "%", POWK = "^",
					IDIVK = "//", ANDK = "and", ORK = "or",
				}
				for _, ins in ipairs(ir.instructions) do
					local op, r, e = ins.op, ins.registers, ins.operands
					local a, b, c = r[1], r[2], r[3]
					if op == "NOP" or op == "BREAK" or op == "COVERAGE" or op == "NATIVECALL" or op:match("^FASTCALL") or op == "PREPVARARGS" then
						continue
					elseif op == "LOADNIL" then
						setValue(a, { code = "nil" })
					elseif op == "LOADB" then
						if (e[2] or 0) ~= 0 then return fail(ins, "LOADB skip-count control flow is unsupported") end
						setValue(a, { code = ((e[1] or 0) ~= 0) and "true" or "false" })
					elseif op == "LOADN" then
						setValue(a, { code = tostring(e[1] or 0) })
					elseif op == "LOADK" then
						local value, err = constant(e[1]); if not value then return fail(ins, err) end
						setValue(a, { code = value })
					elseif op == "MOVE" then
						local value, err = getReg(b, ins); if not value then return nil, err end
						setValue(a, value)
					elseif op == "GETGLOBAL" then
						local item = constants[(e[1] or -1) + 1]
						local value = item and globalExpr(item.value)
						if not value then return fail(ins, "invalid GETGLOBAL constant") end
						setGlobalValue(a, value, ins)
					elseif op == "SETGLOBAL" then
						local item = constants[(e[1] or -1) + 1]
						local lhs = item and globalExpr(item.value)
						local rhs, err = getCode(a, ins); if not rhs then return nil, err end
						if not lhs then return fail(ins, "invalid SETGLOBAL constant") end
						lines[#lines + 1] = lhs .. " = " .. rhs
					elseif op == "GETIMPORT" then
						local item = constants[(e[1] or -1) + 1]
						local value = item and item.value
						local validImport = validIdentifierPath(value)
						if type(value) == "string" then
							local servicePrefix, suffix = value:match('^(game:GetService%("[%w_]+"%))(.*)$')
							if servicePrefix then
								local validSuffix = true
								while suffix ~= "" do
									local segment, tail = suffix:match("^%.([%a_][%w_]*)(.*)$")
									if not segment or safeKeywords[segment] then validSuffix = false; break end
									suffix = tail
								end
								if validSuffix then validImport = true end
							end
						end
						if not validImport then
							return fail(ins, "GETIMPORT path is not a validated identifier path")
						end
						setGlobalValue(a, value, ins)
					elseif op == "NEWTABLE" then
						setValue(a, temp("{}", "tbl"))
					elseif op == "GETTABLE" then
						local object, err1 = getCode(b, ins); if not object then return nil, err1 end
						local key, err2 = getCode(c, ins); if not key then return nil, err2 end
						setValue(a, temp(object .. "[" .. key .. "]"))
					elseif op == "SETTABLE" then
						local value, err1 = getCode(a, ins); if not value then return nil, err1 end
						local object, err2 = getCode(b, ins); if not object then return nil, err2 end
						local key, err3 = getCode(c, ins); if not key then return nil, err3 end
						lines[#lines + 1] = object .. "[" .. key .. "] = " .. value
					elseif op == "GETTABLEKS" then
						local object, err = getCode(b, ins); if not object then return nil, err end
						local item = constants[(e[2] or -1) + 1]
						if not item or type(item.value) ~= "string" then return fail(ins, "GETTABLEKS key constant is invalid") end
						setValue(a, temp(object .. keyExpr(item.value)))
					elseif op == "SETTABLEKS" then
						local value, err1 = getCode(a, ins); if not value then return nil, err1 end
						local object, err2 = getCode(b, ins); if not object then return nil, err2 end
						local item = constants[(e[2] or -1) + 1]
						if not item or type(item.value) ~= "string" then return fail(ins, "SETTABLEKS key constant is invalid") end
						lines[#lines + 1] = object .. keyExpr(item.value) .. " = " .. value
					elseif op == "GETTABLEN" then
						local object, err = getCode(b, ins); if not object then return nil, err end
						setValue(a, temp(object .. "[" .. tostring((e[1] or 0) + 1) .. "]"))
					elseif op == "SETTABLEN" then
						local value, err1 = getCode(a, ins); if not value then return nil, err1 end
						local object, err2 = getCode(b, ins); if not object then return nil, err2 end
						lines[#lines + 1] = object .. "[" .. tostring((e[1] or 0) + 1) .. "] = " .. value
					elseif binary[op] then
						local left, err1 = getCode(b, ins); if not left then return nil, err1 end
						local right, err2 = getCode(c, ins); if not right then return nil, err2 end
						setValue(a, temp("(" .. left .. " " .. binary[op] .. " " .. right .. ")"))
					elseif binaryK[op] then
						local left, err1 = getCode(b, ins); if not left then return nil, err1 end
						local right, err2 = constant(e[1]); if not right then return fail(ins, err2) end
						setValue(a, temp("(" .. left .. " " .. binaryK[op] .. " " .. right .. ")"))
					elseif op == "SUBRK" or op == "DIVRK" then
						local right, err1 = getCode(b, ins); if not right then return nil, err1 end
						local left, err2 = constant(e[1]); if not left then return fail(ins, err2) end
						setValue(a, temp("(" .. left .. (op == "SUBRK" and " - " or " / ") .. right .. ")"))
					elseif op == "NOT" or op == "MINUS" or op == "LENGTH" then
						local value, err = getCode(b, ins); if not value then return nil, err end
						local expression = op == "NOT" and ("not (" .. value .. ")") or op == "MINUS" and ("- (" .. value .. ")") or ("#(" .. value .. ")")
						setValue(a, temp(expression))
					elseif op == "CONCAT" then
						local parts = {}
						for register = b, c do local value, err = getCode(register, ins); if not value then return nil, err end; parts[#parts + 1] = value end
						setValue(a, temp("(" .. table.concat(parts, " .. ") .. ")"))
					elseif op == "NAMECALL" then
						local receiverValue, receiverErr = getReg(b, ins); if not receiverValue then return nil, receiverErr end
						local receiver = receiverValue.code
						local item = constants[(e[2] or -1) + 1]
						if not item or type(item.value) ~= "string" then return fail(ins, "NAMECALL method constant is invalid") end
						local matchingCall, captureReceiver = false, false
						for look = ins.irIndex + 1, #ir.instructions do
							local future = ir.instructions[look]
							if future.op == "CALL" and future.registers[1] == a then matchingCall = true; break end
							if future.op == "CALL" or future.op == "SETGLOBAL" or future.op == "SETTABLE" or future.op == "SETTABLEKS" or future.op == "SETTABLEN" then captureReceiver = true end
						end
						if not matchingCall then return fail(ins, "NAMECALL is not paired with a matching CALL") end
						if receiverValue.global and captureReceiver then receiver = temp(receiver, "receiver").code end
						setValue(a, { methodCall = true, receiver = receiver, method = item.value })
						setValue(a + 1, { code = receiver })
					elseif op == "CALL" then
						local base = a
						local argCount, resultCount = e[1], e[2]
						if type(argCount) ~= "number" or argCount == 0 then return fail(ins, "open-argument CALL is unsupported") end
						if type(resultCount) ~= "number" or resultCount == 0 or resultCount > 2 then return fail(ins, "open or multiple-result CALL is unsupported") end
						local callee, err = getReg(base, ins); if not callee then return nil, err end
						local args, firstArg = {}, base + 1
						local methodCall = callee.methodCall == true
						if methodCall then firstArg = base + 2 end
						for register = firstArg, base + argCount - 1 do
							local value, valueErr = getCode(register, ins); if not value then return nil, valueErr end
							args[#args + 1] = value
						end
						local callCode
						if methodCall then
							local method = callee.method
							if not method:match("^[%a_][%w_]*$") or safeKeywords[method] then
								return fail(ins, "non-identifier NAMECALL method is unsupported in safe mode")
							end
							callCode = callee.receiver .. ":" .. method .. "(" .. table.concat(args, ", ") .. ")"
						else
							local fn, fnErr = getCode(base, ins); if not fn then return nil, fnErr end
							callCode = fn .. "(" .. table.concat(args, ", ") .. ")"
						end
						if resultCount == 1 then
							lines[#lines + 1] = callCode
							regs[base] = nil
						else
							-- Keep a single-result call as an expression so an adjacent
							-- NAMECALL can become `game:GetService(...):Method(...)`.
							local nextIns = ir.instructions[ins.irIndex + 1]
							if nextIns and nextIns.op == "NAMECALL" and nextIns.registers[2] == base then
								setValue(base, { code = callCode })
							else
								setValue(base, temp(callCode, "call"))
							end
						end
					elseif op == "RETURN" then
						local count = e[1] or 0
						if count == 0 then return fail(ins, "open RETURN is unsupported") end
						if count == 1 then
							lines[#lines + 1] = "return"
						else
							local values = {}
							for register = a, a + count - 2 do local value, err = getCode(register, ins); if not value then return nil, err end; values[#values + 1] = value end
							lines[#lines + 1] = "return " .. table.concat(values, ", ")
						end
					else
						return fail(ins, "opcode passed validation but has no safe source lowering")
					end
				end
				if #lines == 0 then return "-- Empty function body (safe subset)" end
				return "-- Decompiled by Zuka safe subset. Requires the original Luau/Roblox runtime context.\n" .. table.concat(lines, "\n")
			end

			local function manager(proceed, issue)
				if proceed then
					-- Safe mode bypasses every legacy text-rewrite/declaration-recovery
					-- pass. Its source is already generated from semantic values; running
					-- regex rewrites afterward would reintroduce the register bugs this
					-- mode is specifically designed to avoid.
					if type(options) == "table" and options.mode == "safe" then
						local ok, safeResult = pcall(function()
							local mainProtoId, registerActions, protoTable = organize()
							local output, safeError = decompileSafeSubset(mainProtoId, registerActions, protoTable)
							if not output then error(safeError, 0) end
							return output
						end)
						if ok then return safeResult end
						return "-- SAFE DECOMPILATION REFUSED:\n-- " .. tostring(safeResult)
					end
					local startTime = os.clock()
					local result
					local ok, res = pcall(function()
						local mainProtoId, registerActions, protoTable = organize()
						if type(options) == "table" and options.mode == "safe" then
							local safeResult, safeError = decompileSafeSubset(mainProtoId, registerActions, protoTable)
							if not safeResult then
								error("SAFE DECOMPILATION REFUSED: " .. tostring(safeError), 0)
							end
							return safeResult
						end
						return finalize(mainProtoId, registerActions, protoTable)
					end)
					result = ok and res or ((type(options) == "table" and options.mode == "safe") and ("-- SAFE DECOMPILATION REFUSED:\n-- " .. tostring(res)) or ("-- RUNTIME ERROR:\n-- " .. tostring(res)))
					local _svcNames = {
						Workspace = "workspace",
						Players = 'game:GetService("Players")',
						ReplicatedStorage = 'game:GetService("ReplicatedStorage")',
						ReplicatedFirst = 'game:GetService("ReplicatedFirst")',
						ServerStorage = 'game:GetService("ServerStorage")',
						ServerScriptService = 'game:GetService("ServerScriptService")',
						StarterGui = 'game:GetService("StarterGui")',
						StarterPack = 'game:GetService("StarterPack")',
						StarterPlayer = 'game:GetService("StarterPlayer")',
						Lighting = 'game:GetService("Lighting")',
						SoundService = 'game:GetService("SoundService")',
						RunService = 'game:GetService("RunService")',
						UserInputService = 'game:GetService("UserInputService")',
						TweenService = 'game:GetService("TweenService")',
						HttpService = 'game:GetService("HttpService")',
						MarketplaceService = 'game:GetService("MarketplaceService")',
						TeleportService = 'game:GetService("TeleportService")',
						CollectionService = 'game:GetService("CollectionService")',
					}
					local rawLines = {}
					for line in (result .. "\n"):gmatch("[^\n]*\n") do
						rawLines[#rawLines + 1] = line:gsub("\n$", "")
					end
					local function reconstructRegisterIR(lines)
						local regPat = "v%d+_?%d*"
						local function isRegister(name)
							return name and name:match("^" .. regPat .. "$") ~= nil
						end
						local function assignment(line)
							local ind, kw, reg, rhs = line:match("^(%s*)(local%s+)?(" .. regPat .. ")%s*=%s*(.-)%s*$")
							if not reg then
								return nil
							end
							return { indent = ind, localKw = kw, reg = reg, rhs = rhs }
						end
						local function tokenCount(text, reg)
							local n = 0
							local ep = reg:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
							for _ in text:gmatch("%f[%w_]" .. ep .. "%f[^%w_]") do
								n += 1
							end
							return n
						end
						local function containsToken(text, reg)
							return tokenCount(text, reg) > 0
						end
						local function replaceToken(text, reg, value)
							local ep = reg:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
							local rp = value:gsub("%%", "%%%%")
							return text:gsub("%f[%w_]" .. ep .. "%f[^%w_]", rp, 1)
						end
						local function rhsUsesOnly(line, reg)
							local a = assignment(line)
							if a then
								return containsToken(a.rhs, reg)
							end
							return containsToken(line, reg)
						end
						local function safeExpr(expr)
							if expr and expr:match("^%s*{}%s*") then
								return false
							end
							if not expr or expr == "" then
								return false
							end
							if expr:find("--", 1, true) then
								return false
							end
							if expr:find("\n", 1, true) then
								return false
							end
							return true
						end
						local function safeName(name)
							return name and name:match("^[%a_][%w_]*$") and name ~= "game" and name ~= "workspace"
						end
						for _pass = 1, 12 do
							local changed = false
							local latestDef = {}
							for i = 1, #lines do
								local line = lines[i]
								if line then
									local a = assignment(line)
									if a then
										local base, suffix = a.rhs:match("^%s*(v%d+)([%.:].+)$")
										if base and suffix and base ~= a.reg then
											local prev = latestDef[base]
											if prev and lines[prev] and prev < i then
												local pa = assignment(lines[prev])
												if pa and safeExpr(pa.rhs) and not containsToken(pa.rhs, a.reg) then
													local between = false
													for j = prev + 1, i - 1 do
														if lines[j] and containsToken(lines[j], base) then
															between = true
															break
														end
													end
													if not between then
														lines[i] = a.indent
															.. (a.localKw or "")
															.. a.reg
															.. " = "
															.. pa.rhs
															.. suffix
														lines[prev] = nil
														changed = true
													end
												end
											end
										end
										latestDef[a.reg] = i
									end
								end
							end
							local lastDef = {}
							for i = 1, #lines do
								local line = lines[i]
								if line then
									local a = assignment(line)
									if a then
										local base, suffix = a.rhs:match("^%s*(" .. regPat .. ")([%.:].+)$")
										if base == a.reg and suffix then
											local prev = lastDef[a.reg]
											if prev and lines[prev] then
												local pa = assignment(lines[prev])
												if pa and safeExpr(pa.rhs) and not containsToken(pa.rhs, a.reg) then
													local betweenUses = false
													for j = prev + 1, i - 1 do
														if lines[j] and containsToken(lines[j], a.reg) then
															betweenUses = true
															break
														end
													end
													if not betweenUses then
														a.rhs = pa.rhs .. suffix
														lines[i] = a.indent
															.. (a.localKw or "")
															.. a.reg
															.. " = "
															.. a.rhs
														lines[prev] = nil
														changed = true
													end
												end
											end
										end
										lastDef[a.reg] = i
									end
								end
							end
							local defs = {}
							local uses = {}
							for i = 1, #lines do
								local line = lines[i]
								if line then
									local a = assignment(line)
									if a and safeExpr(a.rhs) then
										defs[a.reg] = { index = i, rhs = a.rhs, indent = a.indent, localKw = a.localKw }
									end
									for reg in line:gmatch("%f[%w_](v%d+_?%d*)%f[^%w_]") do
										uses[reg] = (uses[reg] or 0) + 1
									end
								end
							end
							for reg, d in pairs(defs) do
								local totalUses = uses[reg] or 0
								if totalUses == 2 then
									local consumer = nil
									for j = d.index + 1, #lines do
										if lines[j] and rhsUsesOnly(lines[j], reg) then
											consumer = j
											break
										end
									end
									if
										consumer
										and consumer ~= d.index
										and safeExpr(d.rhs)
										and not containsToken(d.rhs, reg)
									then
										local ca = assignment(lines[consumer])
										if not ca or containsToken(ca.rhs, reg) then
											lines[consumer] = replaceToken(lines[consumer], reg, d.rhs)
											lines[d.index] = nil
											changed = true
										end
									end
								end
							end
							if not changed then
								break
							end
						end
						return lines
					end
					reconstructRegisterIR(rawLines)
					local function escpat(s)
						return s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
					end
					local function escrep(s)
						return (s:gsub("%%", "%%%%"))
					end
					local function nextNonBlank(start)
						local j = start
						while j <= #rawLines and (rawLines[j] == nil or rawLines[j]:match("^%s*$")) do
							j += 1
						end
						return j
					end
					do
						local i = 1
						while i <= #rawLines do
							local line = rawLines[i]
							if line then
								local cond = line:match("^%s*if%s+(.-)%s+then%s*%-%-.*$")
									or line:match("^%s*if%s+(.-)%s+then%s*$")
								if cond then
									local gt = tonumber(line:match("%-%-.*goto #(%d+)"))
									if gt then
										for j = i + 1, math.min(i + 400, #rawLines) do
											local jl = rawLines[j]
											if jl and jl:match("^%s*%-%- jump back to #%d+%s*$") then
												if gt >= j then
													local ind = line:match("^(%s*)")
													rawLines[i] = ind .. "while " .. cond .. " do"
													rawLines[j] = ind .. "end"
												end
												break
											end
										end
									end
								end
							end
							i += 1
						end
					end
					do
						local i = 1
						while i <= #rawLines do
							local line = rawLines[i]
							if line and line:match("^%s*%-%- jump back to #%d+%s*$") then
								for back = 1, 4 do
									local prev = rawLines[i - back]
									if not prev then
										break
									end
									local cond, tgt = prev:match("^%s*if%s+(.-)%s+then%s*%-%- goto #(%d+)%s*$")
									if cond and tonumber(tgt) == i + 1 then
										local ind = prev:match("^(%s*)")
										rawLines[i - back] = ind .. "until " .. cond
										rawLines[i] = nil
										break
									end
								end
							end
							i += 1
						end
					end
					do
						for lineIndex = 1, #rawLines do
							local line = rawLines[lineIndex]
							if line and line:match("^%s*repeat%s*$") then
								local nextIndex = lineIndex + 1
								while
									nextIndex <= #rawLines
									and (not rawLines[nextIndex] or rawLines[nextIndex]:match("^%s*$"))
								do
									nextIndex += 1
								end
								local untilLine = rawLines[nextIndex]
								if untilLine then
									local prefix, bound, variable, operator, delta = untilLine:match(
										"^(%s*until%s+)(.-%s*[<>=~]+%s*)(v[%w_]+)%s*([%+%-])%s*(%d+)%s*$"
									)
									if prefix and bound and variable and delta then
										local indent = line:match("^(%s*)") or ""
										rawLines[lineIndex] = line
											.. "\n"
											.. indent
											.. "\t"
											.. variable
											.. " = "
											.. variable
											.. " "
											.. operator
											.. " "
											.. delta
										rawLines[nextIndex] = prefix .. bound .. variable
									end
								end
							end
						end
					end
					local function tryFoldSelfChain(i)
						local line = rawLines[i]
						if not line then
							return false
						end
						local indent, localKw, reg, rhs = line:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(.+)%s*$")
						if not reg or not rhs then
							return false
						end
						local ep = escpat(reg)
						local suffix = rhs:match("^" .. ep .. "([%.:].+)$")
						if not suffix then
							return false
						end
						local j = i - 1
						while j >= 1 and (rawLines[j] == nil or rawLines[j]:match("^%s*$")) do
							j -= 1
						end
						if j < 1 or not rawLines[j] then
							return false
						end
						local prevIndent, prevLocal, prevReg, prevVal =
							rawLines[j]:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(.+)%s*$")
						if prevReg ~= reg or not prevVal then
							return false
						end
						local prevUses = 0
						for _ in prevVal:gmatch(ep) do
							prevUses += 1
						end
						if prevUses > 0 then
							return false
						end
						rawLines[j] = prevIndent .. (prevLocal or "") .. reg .. " = " .. prevVal .. suffix
						rawLines[i] = nil
						return true
					end
					local function tryCollapse(i)
						local line = rawLines[i]
						if not line then
							return false
						end
						local reg, lit
						reg, lit = line:match('^%s*(v%d+_?%d*) = (".-")%s*$')
						if not reg then
							reg, lit = line:match("^%s*(v%d+_?%d*) = (%-?%d+%.?%d*)%s*$")
						end
						if not reg then
							reg, lit = line:match("^%s*(v%d+_?%d*) = (true)%s*$")
						end
						if not reg then
							reg, lit = line:match("^%s*(v%d+_?%d*) = (false)%s*$")
						end
						if not reg then
							reg, lit = line:match("^%s*(v%d+_?%d*) = (nil)%s*$")
						end
						if not reg then
							reg, lit = line:match("^%s*(v%d+_?%d*) = ([%a_][%w_%.]*)%s*$")
						end
						if not reg then
							return false
						end
						local ep = escpat(reg)
						local j = i + 1
						local skipped = 0
						while j <= #rawLines and skipped < 32 do
							local mid = rawLines[j]
							if mid == nil then
								j += 1
								continue
							end
							if mid:match("^%s*$") then
								j += 1
								skipped += 1
								continue
							end
							if mid:find(ep) then
								break
							end
							local isSimpleAssign = mid:match('^%s*v%d+_?%d*%s*=%s*".-"%s*$')
								or mid:match("^%s*v%d+_?%d*%s*=%s*%-?%d+%.?%d*%s*$")
								or mid:match("^%s*v%d+_?%d*%s*=%s*true%s*$")
								or mid:match("^%s*v%d+_?%d*%s*=%s*false%s*$")
								or mid:match("^%s*v%d+_?%d*%s*=%s*nil%s*$")
								or mid:match("^%s*v%d+_?%d*%s*=%s*[%a_][%w_%.]*%s*$")
							if isSimpleAssign then
								j += 1
								skipped += 1
								continue
							end
							break
						end
						if j > #rawLines or not rawLines[j] then
							return false
						end
						local nxt = rawLines[j]
						local cnt = 0
						for _ in nxt:gmatch(ep) do
							cnt += 1
						end
						if cnt ~= 1 then
							return false
						end
						if nxt:match("^%s*" .. ep .. "%s*=") then
							return false
						end
						rawLines[j] = nxt:gsub(ep, escrep(lit), 1)
						rawLines[i] = nil
						return true
					end
					local function tryFoldRegisterChain(i)
						local line = rawLines[i]
						if not line then
							return false
						end
						local indent, localKw, reg, rhs = line:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(.+)%s*$")
						if not reg or not rhs then
							return false
						end
						local ep = escpat(reg)
						local suffix = rhs:match("^" .. ep .. "([%.:].+)$")
						if suffix then
							local j = i + 1
							while j <= #rawLines and (rawLines[j] == nil or rawLines[j]:match("^%s*$")) do
								j += 1
							end
							if j <= #rawLines and rawLines[j] then
								local ni, nk, nr, nrhs =
									rawLines[j]:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(.+)%s*$")
								if nr == reg and nrhs then
									local np = nrhs:match("^" .. ep .. "([%.:].+)$")
									if np then
										return false
									end
								end
							end
						end
						local j = i + 1
						while j <= #rawLines and (rawLines[j] == nil or rawLines[j]:match("^%s*$")) do
							j += 1
						end
						if j <= #rawLines and rawLines[j] then
							local _, _, nextReg, nextRhs =
								rawLines[j]:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(.+)%s*$")
							if nextReg == reg and nextRhs then
								local nextSuffix = nextRhs:match("^" .. ep .. "([%.:].+)$")
								if nextSuffix then
									if not rhs:find(ep) then
										rawLines[i] = indent .. (localKw or "") .. reg .. " = " .. rhs .. nextSuffix
										rawLines[j] = nil
										return true
									end
								end
							end
						end
						return false
					end
					local function tryFoldExpression(i)
						local line = rawLines[i]
						if not line then
							return false
						end
						local reg, expr = line:match("^%s*local%s+(v%d+_?%d*)%s*=%s*(.+)%s*$")
						if not reg then
							reg, expr = line:match("^%s*(v%d+_?%d*)%s*=%s*(.+)%s*$")
						end
						if not reg or not expr or expr:match("^%s*{}%s*") then
							return false
						end
						local ep = escpat(reg)
						local j = nextNonBlank(i + 1)
						if j > #rawLines or not rawLines[j] then
							return false
						end
						local nxt = rawLines[j]
						local cnt = 0
						for _ in nxt:gmatch(ep) do
							cnt += 1
						end
						if
							cnt ~= 1
							or nxt:match("^%s*local%s+" .. ep .. "%s*=")
							or nxt:match("^%s*" .. ep .. "%s*=")
						then
							return false
						end
						rawLines[j] = nxt:gsub(ep, escrep(expr), 1)
						rawLines[i] = nil
						return true
					end
					local function tryFoldField(i)
						local line = rawLines[i]
						if not line then
							return false
						end
						local lreg, src, field = line:match("^%s*local%s+(v%d+_?%d*) = (v%d+_?%d*)%.([%a_][%w_]*)%s*$")
						if not lreg then
							lreg, src, field = line:match("^%s*(v%d+_?%d*) = (v%d+_?%d*)%.([%a_][%w_]*)%s*$")
						end
						if not lreg then
							lreg, src, field = line:match("^%s*(v%d+_?%d*) = (v%d+_?%d*)%[(.-)%]%s*$")
							if lreg then
								field = "[" .. field .. "]"
							else
								return false
							end
						else
							field = "." .. field
						end
						local j = nextNonBlank(i + 1)
						if j > #rawLines then
							return false
						end
						local nxt = rawLines[j]
						local ep = escpat(lreg)
						local cnt = 0
						for _ in nxt:gmatch(ep) do
							cnt += 1
						end
						if cnt ~= 1 then
							return false
						end
						if nxt:match("^%s*" .. ep .. "%s*=") then
							return false
						end
						rawLines[j] = nxt:gsub(ep, escrep(src .. field), 1)
						rawLines[i] = nil
						return true
					end
					local function tryFoldUpv(i)
						local line = rawLines[i]
						if not line then
							return false
						end
						local reg = line:match("^%s*(upv_%d+)%s*=")
						if not reg then
							return false
						end
						local val = line:match("^%s*upv_%d+%s*=%s*(.-)%s*$")
						if not val or val == "" then
							return false
						end
						local j = nextNonBlank(i + 1)
						if j > #rawLines or not rawLines[j] then
							return false
						end
						local nxt = rawLines[j]
						local ep = escpat(reg)
						local cnt = 0
						for _ in nxt:gmatch(ep) do
							cnt += 1
						end
						if cnt ~= 1 then
							return false
						end
						if nxt:match("^%s*" .. ep .. "%s*=") then
							return false
						end
						rawLines[j] = nxt:gsub(ep, escrep(val), 1)
						rawLines[i] = nil
						return true
					end
					do
						local changed = true
						local guard = 0
						while changed and guard < 20 do
							changed = false
							guard += 1
							for i = 1, #rawLines do
								if tryFoldRegisterChain(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryFoldRegisterChain(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryCollapse(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryFoldExpression(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryFoldField(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryFoldUpv(i) then
									changed = true
								end
							end
						end
					end
					do
						local foldKeywords = {}
						for word in
							("and break continue do else elseif end false for function if in local nil not or repeat return then true until while export type"):gmatch(
								"%S+"
							)
						do
							foldKeywords[word] = true
						end
						local function fmtKey(k)
							if type(k) == "number" then
								return ("[%d] = "):format(k)
							end
							if k:match("^[%a_][%w_]*$") and not foldKeywords[k] then
								return k .. " = "
							end
							return ("[%q] = "):format(k)
						end
						local i = 1
						while i <= #rawLines do
							local line = rawLines[i]
							if line and line:match("^%s*v%d+_?%d* = {}%s*$") then
								local tbl = line:match("^%s*(v%d+_?%d*)")
								local ep = escpat(tbl)
								local entries, j = {}, i + 1
								while j <= #rawLines do
									local nl = rawLines[j]
									if nl == nil then
										j += 1
										continue
									end
									if nl:match("^%s*$") then
										j += 1
										continue
									end
									local key, val = nl:match("^%s*" .. ep .. "%.([%a_][%w_]*)%s*=%s*(.+)$")
									if not key then
										key, val = nl:match("^%s*" .. ep .. '%["([^"]+)"%]%s*=%s*(.+)$')
									end
									local numkey
									if not key then
										numkey, val = nl:match("^%s*" .. ep .. "%[(%d+)%]%s*=%s*(.+)$")
										key = numkey
									end
									if key and val then
										entries[#entries + 1] = {
											key = key,
											val = val:match("^(.-)%s*$"),
											idx = j,
											num = numkey ~= nil,
										}
										j += 1
									else
										break
									end
								end
								if #entries >= 1 then
									local parts, allNum = {}, true
									for _, e in ipairs(entries) do
										if not e.num then
											allNum = false
										end
									end
									for _, e in ipairs(entries) do
										parts[#parts + 1] = allNum and e.val
											or (e.num and fmtKey(tonumber(e.key)) .. e.val or fmtKey(e.key) .. e.val)
										rawLines[e.idx] = nil
									end
									local ind = line:match("^(%s*)")
									if #parts <= 4 then
										rawLines[i] = ind .. tbl .. " = { " .. table.concat(parts, ", ") .. " }"
									else
										rawLines[i] = ind
											.. tbl
											.. " = {\n"
											.. ind
											.. "\t"
											.. table.concat(parts, ",\n" .. ind .. "\t")
											.. "\n"
											.. ind
											.. "}"
									end
								end
							end
							i += 1
						end
					end
					do
						local changed = true
						local guard = 0
						while changed and guard < 10 do
							changed = false
							guard += 1
							for i = 1, #rawLines do
								if tryCollapse(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryFoldField(i) then
									changed = true
								end
							end
							for i = 1, #rawLines do
								if tryFoldUpv(i) then
									changed = true
								end
							end
						end
					end
					do
						for i = 1, #rawLines do
							local line = rawLines[i]
							local reg = line and line:match("^%s*local%s+(v%d+_?%d*)%s*$")
							if reg then
								local ep = escpat(reg)
								local used = false
								for j = i + 1, #rawLines do
									local other = rawLines[j]
									if other and other:find(ep) then
										used = true
										break
									end
								end
								if not used then
									rawLines[i] = nil
								end
							end
						end
					end
					local pass2 = {}
					for idx = 1, #rawLines do
						local line = rawLines[idx]
						if not line then
							continue
						end
						local s = line:match("^%s*(.-)%s*$")
						if s:match("^%-%- goto #%d+$") then
							continue
						end
						if s:match("^%-%- jump") then
							continue
						end
						if s:match("^%-%- :.*%(udata%)$") then
							continue
						end
						if s:match("^%-%- upvalue capture$") then
							continue
						end
						if s:match("^%-%- clear captures") then
							continue
						end
						if s:match("^%-%- FASTCALL") then
							continue
						end
						if s:match("^%-%- coverage") then
							continue
						end
						if s:match("^%-%- :[%a_][%w_]*%s*$") then
							continue
						end
						if s:match("^%-%- :[%a_][%w_]* %(udata%)%s*$") then
							continue
						end
						line = line:gsub("%s*%-%- goto #%d+", "")
						line = line:gsub("%s*%-%- end at #%d+", "")
						line = line:gsub("%s*%-%- iterate %+ jump to #%d+", "")
						pass2[#pass2 + 1] = line
					end
					local pass2b = {}
					for _, line in ipairs(pass2) do
						local r = line
						do
							local ind, rest = r:match("^(%s*)for v%d+_?%d* = (.+)$")
							if ind then
								r = ind .. "for i = " .. rest
							end
						end
						do
							local ind, rest = r:match("^(%s*)for v%d+_?%d*, v%d+_?%d* in pairs(.+)$")
							if ind then
								r = ind .. "for k, v in pairs" .. rest
							end
						end
						do
							local ind, rest = r:match("^(%s*)for v%d+_?%d*, v%d+_?%d* in ipairs(.+)$")
							if ind then
								r = ind .. "for i, v in ipairs" .. rest
							end
						end
						do
							local ind, iter = r:match("^(%s*)for v%d+_?%d*, v%d+_?%d* in (v%d+_?%d*) do%s*$")
							if ind then
								r = ind .. "for k, v in " .. iter .. " do"
							end
						end
						pass2b[#pass2b + 1] = r
					end
					local pass3 = {}
					local i3 = 1
					while i3 <= #pass2b do
						local line = pass2b[i3]
						local nxt = pass2b[i3 + 1]
						local s = line and line:match("^%s*(.-)%s*$") or ""
						local isNil = s:match("^v%d+_?%d* = nil") or s:match("^local v%d+_?%d* = nil")
						local nxtFor = nxt and nxt:match("^%s*for%s+")
						if isNil and nxtFor then
							i3 += 1
						else
							pass3[#pass3 + 1] = line
							i3 += 1
						end
					end
					local pass3b = {}
					local i3b = 1
					while i3b <= #pass3 do
						local line = pass3[i3b]
						local nxt = pass3[i3b + 1]
						if line and nxt then
							local ind, expr = line:match("^(%s*)%.%.%. = (.+)$")
							if ind and expr and nxt:match("^%s*return %.%.%.$") then
								pass3b[#pass3b + 1] = ind .. "return " .. expr
								i3b += 2
								continue
							end
						end
						pass3b[#pass3b + 1] = line
						i3b += 1
					end
					for i = 1, #pass3b - 1 do
						local line = pass3b[i]
						local nxt = pass3b[i + 1]
						if line and nxt then
							local ind, fnreg, callee = line:match("^(%s*)(v%d+_?%d*)%s*=%s*([%a_][%w_]*)%s*$")
							local outreg, callbase, args = nxt:match("^(%s*)(v%d+_?%d*)%s*=%s*(v%d+_?%d*)%((.*)%)%s*$")
							if fnreg and callee and outreg and callbase == fnreg then
								local argPattern = "[%w_]" .. fnreg .. "[%w_]"
								if args:match("^" .. fnreg .. "%s*,") or args:match(",%s*" .. fnreg .. "%s*$") then
									local prefix = ind or ""
									pass3b[i] = ""
									pass3b[i + 1] = prefix
										.. outreg
										.. " = "
										.. callee
										.. "("
										.. args:gsub("^" .. fnreg, fnreg, 1)
										.. ")"
								end
							end
						end
					end
					for i = 1, #pass3b - 1 do
						local defLine = pass3b[i]
						local callLine = pass3b[i + 1]
						if defLine and callLine then
							local di, dk, freg, fexpr = defLine:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(.-)%s*$")
							local ci, outreg, target, args =
								callLine:match("^(%s*)(v%d+_?%d*)%s*=%s*(v%d+_?%d*)%s*%((.*)%)%s*$")
							if freg and fexpr and ci and target == freg and safeExpr(fexpr) then
								local ep = freg:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
								local uses = 0
								for j = i, #pass3b do
									if pass3b[j] then
										for _ in pass3b[j]:gmatch("%f[%w_]" .. ep .. "%f[^%w_]") do
											uses += 1
										end
									end
								end
								if uses == 2 then
									pass3b[i] = ""
									pass3b[i + 1] = ci .. outreg .. " = " .. fexpr .. "(" .. args .. ")"
									changed = true
								end
							end
						end
					end
					for i = 1, #pass3b - 1 do
						local defLine = pass3b[i]
						local callLine = pass3b[i + 1]
						if defLine and callLine then
							local di, dk, dst, src = defLine:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*(v%d+_?%d*)%s*$")
							local ci, outreg, target, args =
								callLine:match("^(%s*)(v%d+_?%d*)%s*=%s*(v%d+_?%d*)%s*%((.*)%)%s*$")
							if dst and src and ci and target == dst then
								local ep = dst:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
								local uses = 0
								for j = i, #pass3b do
									if pass3b[j] then
										for _ in pass3b[j]:gmatch("%f[%w_]" .. ep .. "%f[^%w_]") do
											uses += 1
										end
									end
								end
								if uses == 2 then
									pass3b[i] = ""
									pass3b[i + 1] = ci .. outreg .. " = " .. src .. "(" .. args .. ")"
									changed = true
								end
							end
						end
					end
					for i, line in ipairs(pass3b) do
						if line then
							local ind, localKw, reg, value =
								line:match("^(%s*)(local%s+)?(v%d+_?%d*)%s*=%s*{%s*__index%s*=%s*(v%d+_?%d*)%s*}%s*$")
							if reg and value and reg == value then
								pass3b[i] = ind .. (localKw or "") .. reg .. " = {}"
								table.insert(pass3b, i + 1, ind .. reg .. ".__index = " .. reg)
							end
						end
					end
					local knownFunctions = {}
					for _, line in ipairs(pass3b) do
						local fn = line:match("^%s*local%s+function%s+([%a_][%w_]*)%s*%(")
						if fn then
							knownFunctions[fn] = true
						end
					end
					for i, line in ipairs(pass3b) do
						if line then
							local target, field, fn = line:match("^(%s*v%d+_?%d*)%.([%a_][%w_]*)%s*=%s*([%a_][%w_]*)$")
							if fn then
								local base = fn:match("^(.+)_([0-9]+)$")
								if base and knownFunctions[base] then
									pass3b[i] = target .. "." .. field .. " = " .. base
								end
							end
						end
					end
					-- Register temporaries belong to a prototype/function scope, not to
					-- whichever nested branch happens to assign them first. Hoist their
					-- declarations to the owning function body so values written in an
					-- if/else branch remain visible after the branch.
					local pass4 = {}
					for _, line in ipairs(pass3b) do
						pass4[#pass4 + 1] = line
					end
					local topScope = { headerIndex = nil, registers = {}, seen = {} }
					local functionScopes = {}
					local blockStack = {}
					local allScopes = { topScope }
					local function currentScope()
						return functionScopes[#functionScopes] or topScope
					end
					local function isFunctionHeader(code)
						return code:match("^local%s+function%s")
							or code:match("^function%s")
							or code:match("=%s*function%s*%(")
							or code:match("^return%s+function%s*%(")
					end
					for lineIndex, line in ipairs(pass4) do
						local code = line:match("^(.-)%s*%-%-") or line
						code = code:match("^%s*(.-)%s*$") or ""
						if code == "end" then
							local closed = table.remove(blockStack)
							if closed == "function" then
								table.remove(functionScopes)
							end
						elseif code:match("^until%f[%W]") then
							if blockStack[#blockStack] == "repeat" then
								table.remove(blockStack)
							end
						end
						local scope = currentScope()
						local lhs = line:match("^%s*local%s+([^=]+)%s*=")
							or line:match("^%s*([^=]+)%s*=")
						if lhs then
							local names = {}
							local valid = true
							for piece in (lhs .. ","):gmatch("(.-),") do
								local name = piece:match("^%s*(v%d+_?%d*)%s*$")
								if not name then
									valid = false
									break
								end
								names[#names + 1] = name
							end
							if valid and #names > 0 then
								for _, name in ipairs(names) do
									if not scope.seen[name] then
										scope.seen[name] = true
										scope.registers[#scope.registers + 1] = name
									end
								end
								pass4[lineIndex] = line:gsub("^(%s*)local%s+", "%1", 1)
							end
						end
						if isFunctionHeader(code) then
							local fnScope = {
								headerIndex = lineIndex,
								registers = {},
								seen = {},
							}
							functionScopes[#functionScopes + 1] = fnScope
							allScopes[#allScopes + 1] = fnScope
							blockStack[#blockStack + 1] = "function"
						elseif code:match("^if%f[%W].-%s+then%s*$") then
							blockStack[#blockStack + 1] = "if"
						elseif code:match("^for%f[%W].-%s+do%s*$") then
							blockStack[#blockStack + 1] = "for"
						elseif code:match("^while%f[%W].-%s+do%s*$") then
							blockStack[#blockStack + 1] = "while"
						elseif code == "repeat" then
							blockStack[#blockStack + 1] = "repeat"
						elseif code == "do" then
							blockStack[#blockStack + 1] = "do"
						end
					end
					local insertions = {}
					for _, scope in ipairs(allScopes) do
						if #scope.registers > 0 then
							local insertionIndex = scope.headerIndex and (scope.headerIndex + 1) or 1
							local declarations = {}
							for first = 1, #scope.registers, 50 do
								local names = {}
								for k = first, math.min(first + 49, #scope.registers) do
									names[#names + 1] = scope.registers[k]
								end
								declarations[#declarations + 1] =
									"local " .. table.concat(names, ", ")
							end
							insertions[#insertions + 1] = { index = insertionIndex, lines = declarations }
						end
					end
					table.sort(insertions, function(a, b)
						return a.index > b.index
					end)
					for _, insertion in ipairs(insertions) do
						for offset = #insertion.lines, 1, -1 do
							table.insert(pass4, insertion.index, insertion.lines[offset])
						end
					end
					local seen4b = {}
					local pass4b = {}
					for _, line in ipairs(pass4) do
						local reg = line:match("^%s*(upv_%d+)%s*=")
						if reg and not seen4b[reg] then
							seen4b[reg] = true
							line = line:gsub("^(%s*)(upv_%d+%s*=)", "%1local %2", 1)
						end
						pass4b[#pass4b + 1] = line
					end
					for i = 1, #pass4b do
						local line = pass4b[i]
						if line then
							for className, expr in pairs(_svcNames) do
								local pat = 'game:GetService("' .. escpat(className) .. '")'
								if line:find(pat, 1, true) and expr ~= pat then
									line = line:gsub(pat, function()
										return expr
									end)
								end
							end
							pass4b[i] = line
						end
					end
					local final = {}
					local lastBlank = false
					for _, line in ipairs(pass4b) do
						local isBlank = line:match("^%s*$") ~= nil
						if isBlank and lastBlank then
							continue
						end
						lastBlank = isBlank
						final[#final + 1] = line
					end
					local function prettySource(source)
						local formatted = {}
						local depth = 0
						local stack = {}
						local previousCode = ""
						local previousKind = ""
						local function trim(v)
							return (v:gsub("^%s+", ""):gsub("%s+$", ""))
						end
						local function blank()
							if #formatted > 0 and formatted[#formatted] ~= "" then
								formatted[#formatted + 1] = ""
							end
						end
						local function maskedCode(line)
							local out, quote, escaped = {}, nil, false
							local i = 1
							while i <= #line do
								local c, n = line:sub(i, i), line:sub(i + 1, i + 1)
								if quote then
									out[#out + 1] = " "
									if escaped then
										escaped = false
									elseif c == "\\" then
										escaped = true
									elseif c == quote then
										quote = nil
									end
								elseif c == "-" and n == "-" then
									break
								elseif c == '"' or c == "'" then
									quote = c
									out[#out + 1] = " "
								else
									out[#out + 1] = c
								end
								i = i + 1
							end
							return table.concat(out)
						end
						local function begins(code, word)
							return code:match("^" .. word .. "%f[^%w_]") ~= nil
						end
						local function isFunctionStart(code)
							return code:match("^local%s+function%s") ~= nil
								or code:match("^function%s") ~= nil
								or code:match("=%s*function%s*%(") ~= nil
								or code:match("^return%s+function%s*%(") ~= nil
						end
						local function isBlockStart(code)
							if isFunctionStart(code) then
								return "function"
							end
							if begins(code, "if") and code:match("%f[%a]then%s*$") then
								return "if"
							end
							if begins(code, "for") and code:match("%f[%a]do%s*$") then
								return "for"
							end
							if begins(code, "while") and code:match("%f[%a]do%s*$") then
								return "while"
							end
							if begins(code, "repeat") then
								return "repeat"
							end
							if begins(code, "do") and code:match("^do%s*$") then
								return "do"
							end
							return nil
						end
						for raw in (source .. "\n"):gmatch("(.-)\n") do
							local line = trim(raw)
							if line ~= "" then
								local code = maskedCode(line)
								local ending = begins(code, "end") or begins(code, "until")
								local middle = begins(code, "else") or begins(code, "elseif")
								if ending or middle then
									if depth > 0 then
										depth = depth - 1
									end
								end
								local kind = isBlockStart(code)
								if kind == "function" and depth == 0 and #formatted > 0 then
									blank()
								elseif
									begins(code, "return")
									and depth > 0
									and previousCode ~= ""
									and previousKind ~= "function"
									and not begins(previousCode, "return")
									and not begins(previousCode, "else")
									and not begins(previousCode, "elseif")
									and not begins(previousCode, "if")
									and not begins(previousCode, "for")
									and not begins(previousCode, "while")
									and not begins(previousCode, "repeat")
									and not begins(previousCode, "do")
								then
									blank()
								end
								formatted[#formatted + 1] = string.rep("    ", depth) .. line
								if ending then
									if #stack > 0 then
										stack[#stack] = nil
									end
									if depth == 0 then
										blank()
									end
								elseif middle then
									depth = depth + 1
								elseif kind then
									stack[#stack + 1] = kind
									depth = depth + 1
								end
								previousCode, previousKind = code, kind or ""
							end
						end
						while formatted[#formatted] == "" do
							formatted[#formatted] = nil
						end
						return table.concat(formatted, "\n")
					end
					local function nameTopLevelServices(source)
						local lines = string.split(source, "\n")
						local renamed = {}
						local usedNames = {}
						for _, line in ipairs(lines) do
							local name = line:match("^local%s+([%a_][%w_]*)%s*=")
							if name then
								usedNames[name] = true
							end
						end
						local depth = 0
						local function substitute(line)
							for old, new in pairs(renamed) do
								line = line:gsub("(%f[%w_])" .. old .. "(%f[^%w_])", new)
							end
							return line
						end
						for i, line in ipairs(lines) do
							local stripped = line:match("^%s*(.-)%s*$")
							if line:match("^%S") then
								local reg, service = stripped:match(
									"^local%s+(v%d+_?%d*)%s*=%s*game:GetService%([\"']([%a_][%w_]*)[\"']%)$"
								)
								if not reg then
									local base
									reg, base, service = stripped:match(
										"^local%s+(v%d+_?%d*)%s*=%s*(v%d+_?%d*):GetService%([\"']([%a_][%w_]*)[\"']%)$"
									)
									if base and base ~= "v0" then
										reg = nil
									end
								end
								if reg and not usedNames[service] and not renamed[reg] then
									renamed[reg] = service
									usedNames[service] = true
									lines[i] = "local " .. service .. ' = game:GetService("' .. service .. '")'
								else
									lines[i] = substitute(line)
								end
							end
							local indent = #(line:match("^(%s*)") or "")
							if indent > 0 then
								depth = 1
							else
								depth = 0
							end
						end
						return table.concat(lines, "\n")
					end
					local function removeRedundantGameAlias(source)
						local lines = string.split(source, "\n")
						local candidate
						for i, line in ipairs(lines) do
							if line == "local v0 = game" then
								candidate = i
								break
							end
						end
						if not candidate then
							return source
						end
						local hasService = false
						for i = candidate + 1, #lines do
							local line = lines[i]
							if line:match("^local%s+[%a_][%w_]*%s*=%s*game:GetService%(") then
								hasService = true
							end
							if line:match("^local%s+function%s+") then
								break
							end
							if line:match("^v0%f[^%w_]") or line:match("^local%s+[%a_][%w_]*%s*=%s*v0%f[^%w_]") then
								return source
							end
						end
						if not hasService then
							return source
						end
						table.remove(lines, candidate)
						return table.concat(lines, "\n")
					end
					local function declareFunctionRegisters(source)
						local lines = string.split(source, "\n")
						local inFunction, seen, depth = false, {}, 0
						for i, line in ipairs(lines) do
							local indent = #(line:match("^(%s*)") or "")
							local stripped = line:match("^%s*(.-)%s*$")
							if indent == 0 and stripped:match("^local function ") then
								inFunction, seen, depth = true, {}, 1
							elseif inFunction and indent == 0 and stripped == "end" then
								inFunction, seen, depth = false, {}, 0
							elseif inFunction then
								local reg, rhs = nil, nil
								if indent == 4 then
									reg, rhs = stripped:match("^(v%d+_?%d*)%s*=%s*(.+)$")
								end
								if reg and not seen[reg] and not rhs:match("^function%s*%(") then
									if not rhs:find("%f[%w_]" .. reg .. "%f[^%w_]") then
										lines[i] = "    local " .. stripped
									end
								end
								for name in stripped:gmatch("%f[%w_](v%d+_?%d*)%f[^%w_]") do
									seen[name] = true
								end
							end
						end
						return table.concat(lines, "\n")
					end
					result = removeRedundantGameAlias(
						nameTopLevelServices(declareFunctionRegisters(prettySource(table.concat(final, "\n"))))
					)
					local function repairPairsIterator(source)
						local lines = string.split(source, "\n")
						local out, i = {}, 1
						while i <= #lines do
							local header = lines[i]
							local indent, param = header:match("^(%s*)local function genericLoop%((p%d+)%)")
							if indent then
								local finish = i + 1
								while finish <= #lines and lines[finish] ~= indent .. "end" do
									finish += 1
								end
								local body = table.concat(lines, "\n", i + 1, finish - 1)
								local tableReg = body:match("local%s+(v%d+_?%d*)%s*=%s*{}")
								local hasPairs = body:find("=%s*pairs%s*\n") ~= nil
								local hasLoop = body:find("for%s+k%s*,%s*v%s+in%s+pairs%(") ~= nil
								local hasWrite = tableReg
									and body:find(tableReg .. "%[v%d+_?%d*%]%s*=%s*tostring%(") ~= nil
								local hasReturn = tableReg and body:find("return%s+" .. tableReg .. "%s*$") ~= nil
								if
									finish <= #lines
									and tableReg
									and hasPairs
									and hasLoop
									and hasWrite
									and hasReturn
								then
									out[#out + 1] = header
									out[#out + 1] = indent .. "    local " .. tableReg .. " = {}"
									out[#out + 1] = indent .. "    for k, v in pairs(" .. param .. ") do"
									out[#out + 1] = indent .. "        " .. tableReg .. "[k] = tostring(v)"
									out[#out + 1] = indent .. "    end"
									out[#out + 1] = ""
									out[#out + 1] = indent .. "    return " .. tableReg
									out[#out + 1] = indent .. "end"
									i = finish + 1
								else
									out[#out + 1] = lines[i]
									i += 1
								end
							else
								out[#out + 1] = lines[i]
								i += 1
							end
						end
						return table.concat(out, "\n")
					end
					result = repairPairsIterator(result)
					local function repairGuardedCharacterAccess(source)
						local lines = string.split(source, "\n")
						local out, i = {}, 1
						while i <= #lines do
							local header = lines[i]
							local indent, param = header:match("^(%s*)local function robloxTest%((p%d+)%)")
							if not indent then
								out[#out + 1] = header
								i += 1
							else
								local finish = i + 1
								while finish <= #lines and lines[finish] ~= indent .. "end" do
									finish += 1
								end
								local body = {}
								for j = i + 1, math.min(finish - 1, #lines) do
									body[#body + 1] = lines[j]
								end
								local first = 1
								while body[first] and body[first]:match("^%s*$") do
									first += 1
								end
								local guard = body[first] or ""
								local nilAssignment = body[first + 1] or ""
								local closeGuard = body[first + 2] or ""
								local returnIndex = first + 3
								while body[returnIndex] and body[returnIndex]:match("^%s*$") do
									returnIndex += 1
								end
								local returnLine = body[returnIndex] or ""
								local guardedReg = nilAssignment:match("^%s*(v%d+_?%d*)%s*=%s*nil%s*$")
								local valid = finish <= #lines
									and guard:match("^%s*if not " .. param .. " then%s*$")
									and guardedReg
									and closeGuard:match("^%s*end%s*$")
									and returnLine:match("^%s*return%s+" .. guardedReg .. "%s*$")
								if valid then
									body[first + 1] = indent .. "        return nil"
									table.remove(body, returnIndex)
									local hasCharacterGuard = false
									local alias = nil
									for _, line in ipairs(body) do
										if line:find("if " .. param .. ".Character then", 1, true) then
											hasCharacterGuard = true
										end
										local receiver = line:match("(v%d+_?%d*):FindFirstChild")
										if receiver then
											if alias and alias ~= receiver then
												hasCharacterGuard = false
											end
											alias = receiver
										end
									end
									if hasCharacterGuard and alias then
										local defined = false
										for _, line in ipairs(body) do
											if
												line:match("^%s*local%s+" .. alias .. "%s*=")
												or line:match("^%s*" .. alias .. "%s*=")
											then
												defined = true
												break
											end
										end
										if not defined then
											for k, line in ipairs(body) do
												body[k] = line:gsub(
													"%f[%w_]" .. alias .. ":FindFirstChild",
													param .. ".Character:FindFirstChild"
												)
											end
										end
									end
									local returnReg = nil
									for _, line in ipairs(body) do
										returnReg = line:match("^%s*return%s+(v%d+_?%d*)%s*$") or returnReg
									end
									if returnReg then
										local declaration = nil
										for k, line in ipairs(body) do
											if line:match("^%s+local%s+" .. returnReg .. "%s*=") then
												declaration = k
												break
											end
										end
										if declaration then
											body[declaration] = body[declaration]:gsub("^(%s*)local%s+", "%1", 1)
											table.insert(body, first, indent .. "    local " .. returnReg .. " = nil")
										end
									end
								end
								out[#out + 1] = header
								for _, line in ipairs(body) do
									out[#out + 1] = line
								end
								if finish <= #lines then
									out[#out + 1] = lines[finish]
									i = finish + 1
								else
									i = #lines + 1
								end
							end
						end
						return table.concat(out, "\n")
					end
					result = repairGuardedCharacterAccess(result)
					local function repairCharacterLocals(source)
						local lines = string.split(source, "\n")
						local out, i = {}, 1
						while i <= #lines do
							local header = lines[i]
							local indent, param = header:match("^(%s*)local function robloxTest%((p%d+)%)")
							if not indent then
								out[#out + 1] = header
								i += 1
							else
								local finish = i + 1
								while finish <= #lines and lines[finish] ~= indent .. "end" do
									finish += 1
								end
								local body = {}
								for j = i + 1, math.min(finish - 1, #lines) do
									body[#body + 1] = lines[j]
								end
								local joined = table.concat(body, "\n")
								local valid = joined:find("if not " .. param .. " then", 1, true)
									and joined:find("return nil", 1, true)
									and joined:find(param .. ".Character:FindFirstChild", 1, true)
								if valid then
									local seen = {}
									for j, line in ipairs(body) do
										local prefix, reg, rhs = line:match("^(%s*)(v%d+_?%d*)%s*=%s*(.+)$")
										if reg and rhs and rhs:find(param .. ".Character:FindFirstChild", 1, true) then
											if not seen[reg] then
												body[j] = prefix .. "local " .. reg .. " = " .. rhs
												seen[reg] = true
											end
										end
									end
									local last = #body
									while last > 0 and body[last]:match("^%s*$") do
										last -= 1
									end
									if
										last >= 2
										and body[last]:match("^%s*return nil%s*$")
										and body[last - 1]:match("^%s*return%s+[%w_]+%s*$")
									then
										table.remove(body, last)
									end
								end
								out[#out + 1] = header
								for _, line in ipairs(body) do
									out[#out + 1] = line
								end
								if finish <= #lines then
									out[#out + 1] = lines[finish]
									i = finish + 1
								else
									i = #lines + 1
								end
							end
						end
						return table.concat(out, "\n")
					end
					result = repairCharacterLocals(result)
					result = result:gsub(
						"(repeat[ \t]*\n)([ \t]*)(until%s+[^\n]-[<>=~]+%s*)(v%d+_?%d*)(%s*)([%+%-])(%s*)(%d+)([ \t]*\n)",
						function(head, indent, cond, reg, space1, op, space2, delta, trailing)
							return head
								.. indent
								.. "    "
								.. reg
								.. " = "
								.. reg
								.. " "
								.. op
								.. " "
								.. delta
								.. "\n"
								.. indent
								.. cond
								.. reg
								.. trailing
						end
					)
					local function recoverRegisterDeclarationsV37(source)
						local lines = string.split(source, "\n")
						local seen = {}
						local inTopFunction = false
						local function isRegister(name)
							return name:match("^v%d+$") ~= nil or name:match("^v%d+_%d+$") ~= nil
						end
						local function tokens(code)
							local found = {}
							for word in code:gmatch("[%a_][%w_]*") do
								if isRegister(word) then
									found[word] = true
								end
							end
							return found
						end
						local function stripComment(line)
							return line:match("^(.-)%s*%-%-") or line
						end
						for i, line in ipairs(lines) do
							local code = stripComment(line)
							local indent = code:match("^(%s*)") or ""
							if #indent == 0 and code:match("^local function%s+[%w_]+%s*%(") then
								seen = {}
								inTopFunction = true
							elseif #indent == 0 and code:match("^end%s*$") and inTopFunction then
								seen = {}
								inTopFunction = false
							else
								local eligible = (#indent == 0 and not inTopFunction)
									or (#indent == 4 and inTopFunction)
								local lhs, rhs = code:match("^%s*(.-)%s+=%s+(.+)$")
								if eligible and lhs and rhs and not code:match("^%s*local%s+") then
									local names = {}
									local valid = true
									for piece in (lhs .. ","):gmatch("(.-),") do
										local name = piece:match("^%s*([%w_]+)%s*$")
										if not name or not isRegister(name) or seen[name] then
											valid = false
											break
										end
										names[#names + 1] = name
									end
									if #names == 0 then
										valid = false
									end
									local rhsTokens = tokens(rhs)
									for _, name in ipairs(names) do
										if rhsTokens[name] then
											valid = false
										end
									end
									if valid then
										lines[i] = indent .. "local " .. table.concat(names, ", ") .. " = " .. rhs
									end
								end
								for name in pairs(tokens(code)) do
									seen[name] = true
								end
							end
						end
						return table.concat(lines, "\n")
					end
					result = recoverRegisterDeclarationsV37(result)
					if (os.clock() - startTime) >= 10 then
						return Strings.TIMEOUT
					end
					return string.format(Strings.SUCCESS, result)
				else
					if issue == "COMPILATION_FAILURE" then
						local remaining = reader:len() - 1
						return string.format(Strings.COMPILATION_FAILURE, reader:nextString(remaining))
					elseif issue == "UNSUPPORTED_LBC_VERSION" then
						return string.format(
							Strings.UNSUPPORTED_LBC_VERSION,
							bytecodeVersion,
							LuauBytecodeTag.LBC_VERSION_MIN,
							LuauBytecodeTag.LBC_VERSION_MAX
						)
					end
				end
			end
			bytecodeVersion = reader:nextByte()
			if bytecodeVersion == 0 then
				return manager(false, "COMPILATION_FAILURE")
			elseif
				bytecodeVersion >= LuauBytecodeTag.LBC_VERSION_MIN
				and bytecodeVersion <= LuauBytecodeTag.LBC_VERSION_MAX
			then
				return manager(true)
			else
				return manager(false, "UNSUPPORTED_LBC_VERSION")
			end
		end
		local LUA_KW = {
			["and"] = true,
			["break"] = true,
			["do"] = true,
			["else"] = true,
			["elseif"] = true,
			["end"] = true,
			["false"] = true,
			["for"] = true,
			["function"] = true,
			["if"] = true,
			["in"] = true,
			["local"] = true,
			["nil"] = true,
			["not"] = true,
			["or"] = true,
			["repeat"] = true,
			["return"] = true,
			["then"] = true,
			["true"] = true,
			["until"] = true,
			["while"] = true,
		}
		local function escapeString(s)
			return s:gsub('[%c\\"]', function(c)
				if c == "\\" then
					return "\\\\"
				end
				if c == '"' then
					return '\\"'
				end
				if c == "\n" then
					return "\\n"
				end
				if c == "\r" then
					return "\\r"
				end
				if c == "\t" then
					return "\\t"
				end
				if c == "\0" then
					return "\\0"
				end
				return ("\\%d"):format(c:byte())
			end)
		end
		local function fmtKey(k)
			if type(k) == "number" then
				return ("[%d] = "):format(k)
			elseif type(k) == "string" then
				if k:match("^[%a_][%w_]*$") and not LUA_KW[k] then
					return k .. " = "
				end
				return ('["%s"] = '):format(escapeString(k))
			end
			return ("[%s] = "):format(tostring(k))
		end
		local function safeVarName(idx, val)
			local t = type(val):lower()
			if typeof and typeof(val) == "Instance" then
				local ok, nm = pcall(function()
					return val.Name
				end)
				if ok and type(nm) == "string" and nm ~= "" then
					local clean = nm:gsub("[^%w_]", "_")
					if clean:match("^[%a_]") and not LUA_KW[clean] then
						return clean
					end
				end
			end
			local prefix = ({
				boolean = "bool",
				string = "str",
				number = "num",
				table = "tbl",
				["function"] = "fn",
				thread = "thread",
				userdata = "ud",
				buffer = "buf",
			})[t] or t
			return prefix .. tostring(idx)
		end
		ZukDecompile = Decompile
		if not cliMode then
			local env = type(getgenv) == "function" and getgenv() or _G
			local ok, err = pcall(function()
				env._ZUK_DECOMPILE = Decompile
			end)
			if not ok then
				warn("Unable to register _ZUK_DECOMPILE: " .. tostring(err))
			end
		end
	end
	if not cliMode then
		if type(task) == "table" and type(task.defer) == "function" then
			task.defer(initialize)
		else
			initialize()
		end
		return
	end
	initialize()
	local input, output
	local audit = false
	local safeMode = false
	local i = 1
	while i <= #cliArgs do
		local value = cliArgs[i]
		if value == "--audit" then
			audit = true
		elseif value == "--safe" then
			safeMode = true
		elseif value == "-o" or value == "--output" then
			i = i + 1
			output = cliArgs[i]
			if not output then
				error("Missing filename after -o", 0)
			end
		elseif value == "-h" or value == "--help" then
			print("Usage: luau bytecode_source_cli.lua input.luauc [-o output.lua] [--audit] [--safe]")
			return
		elseif not input and type(value) == "string" and value:sub(1, 1) ~= "-" then
			input = value
		else
			error("Unknown argument: " .. tostring(value), 0)
		end
		i = i + 1
	end
	if not input then
		error("Usage: luau bytecode_source_cli.lua input.luauc [-o output.lua] [--audit] [--safe]", 0)
	end
	if output == input then
		error("Output must differ from input", 0)
	end
	if not io or not io.open then
		error("CLI mode requires io.open in your Luau runtime", 0)
	end
	local file, err = io.open(input, "rb")
	if not file then
		error("Cannot read " .. input .. ": " .. tostring(err), 0)
	end
	local bytecode = file:read("*a")
	file:close()
	local result = ZukDecompile(bytecode, safeMode and { mode = "safe" } or nil)
	if audit and type(result) == "string" then
		local findings = 0
		local function report(lineNumber, label, code)
			findings = findings + 1
			print(("[ZUK AUDIT] line %d [%s] %s"):format(lineNumber, label, code))
		end
		local scopes = { {} }
		local function enterScope()
			scopes[#scopes + 1] = {}
		end
		local function leaveScope()
			if #scopes > 1 then
				scopes[#scopes] = nil
			end
		end
		local function declare(name)
			if name:match("^v%d+_?%d*$") then
				scopes[#scopes][name] = true
			end
		end
		local function visible(name)
			for depth = #scopes, 1, -1 do
				if scopes[depth][name] then
					return true
				end
			end
			return false
		end
		local function namesInList(list, callback)
			for name in list:gmatch("[a-zA-Z_][a-zA-Z_0-9]*") do
				callback(name)
			end
		end
		local prevReturn = false
		local lineNumber = 0
		for line in (result .. "\n"):gmatch("(.-)\n") do
			lineNumber = lineNumber + 1
			local code = line:match("^(.-)%s*%-%-") or line
			local trimmed = code:match("^%s*(.-)%s*$")
			if trimmed:find("upv_%d+") then
				report(lineNumber, "unresolved-upvalue", trimmed)
			end
			if trimmed == "end" or trimmed:match("^end[%s,%)]+") or trimmed:match("^until%s") then
				leaveScope()
			elseif trimmed == "else" or trimmed:match("^elseif%s") then
				leaveScope()
				enterScope()
			end
			local lhs = trimmed:match("^([%w_,%s]+)%s*=")
			if lhs and not trimmed:match("^local%s") then
				local missing = {}
				namesInList(lhs, function(name)
					if name:match("^v%d+_?%d*$") and not visible(name) then
						missing[#missing + 1] = name
					end
				end)
				if #missing > 0 then
					report(lineNumber, "bare-register-assignment", trimmed)
				end
			end
			local localNames = trimmed:match("^local%s+([%w_,%s]+)%s*=")
			if localNames then
				namesInList(localNames, declare)
			end
			local functionName = trimmed:match("^local%s+function%s+([%w_]+)")
			if functionName then
				declare(functionName)
			end
			if trimmed:match("^return%s") and prevReturn then
				report(lineNumber, "consecutive-return", trimmed)
			end
			if trimmed ~= "" then
				prevReturn = trimmed:match("^return%s") ~= nil
			end
			local params = trimmed:match("^local%s+function%s+[%w_]+%s*%((.-)%)")
				or trimmed:match("^function%s+[%w_%.:]+%s*%((.-)%)")
				or trimmed:match("=%s*function%s*%((.-)%)")
			local loopVars = trimmed:match("^for%s+(.+)%s+in%s+.+%s+do$")
				or trimmed:match("^for%s+([%w_]+)%s*=%s*.+%s+do$")
			if params or loopVars then
				enterScope()
				namesInList(params or loopVars, declare)
			elseif
				trimmed:match("^if%s+.+%s+then$")
				or trimmed:match("^while%s+.+%s+do$")
				or trimmed == "repeat"
				or trimmed == "do"
			then
				enterScope()
			end
		end
		print(("[ZUK AUDIT] %d finding(s); decompiled output unchanged"):format(findings))
	end
	if not output then
		print(result)
		return result
	end
	local target, writeErr = io.open(output, "wb")
	if not target then
		error("Cannot write " .. output .. ": " .. tostring(writeErr), 0)
	end
	target:write(result)
	target:close()
	print("Decompiled " .. input .. " -> " .. output)
	return result
end
return main(...)
