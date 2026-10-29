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
		do
			local raw = Luau.OpCode
			local encoded = {}
			for i, v in raw do
				local case = bit32.band((i - 1) * CASE_MULTIPLIER, 0xFF)
				encoded[case] = v
			end
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
		local LuauOpCode = Luau.OpCode
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
		local function Decompile(bytecode)
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
						local function reg(act, regs, extra, hide)
							table.insert(
								protoRegisterActions,
								{ usedRegisters = regs or {}, extraData = extra, opCode = act, hide = hide }
							)
						end
						for idx, instruction in ipairs(instructions) do
							if auxSkip then
								auxSkip = false
								continue
							end
							local oci = LuauOpCode[Luau:INSN_OP(instruction)]
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
									local regs = { A, B }
									for k = 1, C - 1 do
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
									table.insert(regs, A + k)
								end
								reg(oci, regs, { sD, aux })
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
						local actions = protoActions.actions
						local proto = protoActions.proto
						local lineInfo = proto.instructionLineInfo
						local inner = proto.innerProtos
						local consts = proto.constants
						local caps = proto.captures
						local pflags = proto.flags
						local numParams = proto.numParams
						local flow = { numeric = {}, generic = {}, backedges = {}, targets = {} }
						for pc, act in ipairs(actions) do
							local op = act.opCode and act.opCode.name
							local delta = act.extraData and act.extraData[1]
							if
								type(delta) == "number"
								and (
									op == "FORNPREP"
									or op == "FORGPREP"
									or op == "FORNLOOP"
									or op == "FORGLOOP"
									or op == "JUMPBACK"
									or op == "JUMP"
								)
							then
								local dest = pc + delta + 1
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
						totalParameters += numParams
						if proto.main and pflags and pflags.native then
							emit("--!native\n")
						end
						local function buildRegNames(instrIdx)
							local names = {}
							if proto.debugLocals then
								for _, dl in ipairs(proto.debugLocals) do
									if instrIdx >= dl.startPC and instrIdx <= dl.endPC then
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
						local function getSourceRegisters(opName, ur2, ed2)
							if opName == "SETTABLEKS" or opName == "SETTABLEN" then
								return ur2 and { ur2[1], ur2[2] } or {}
							elseif opName == "SETTABLE" then
								return ur2 and { ur2[1], ur2[2], ur2[3] } or {}
							elseif opName == "SETGLOBAL" or opName == "SETUPVAL" then
								return ur2 and { ur2[1] } or {}
							end
							if opName == "CALL" or opName == "CALLFB" then
								local srcs = {}
								local base = ur2 and ur2[1]
								if base ~= nil then
									srcs[#srcs + 1] = base
									local count = (ed2 and ed2[1]) or 1
									for k = 1, count - 1 do
										srcs[#srcs + 1] = base + k
									end
								end
								return srcs
							end
							if opName == "NAMECALL" then
								if ur2 and ur2[2] ~= nil then
									return { ur2[2] }
								end
								return {}
							end
							if opName == "MOVE" then
								if ur2 and ur2[2] ~= nil then
									return { ur2[2] }
								end
								return {}
							end
							local srcs = {}
							if ur2 then
								for k = 2, #ur2 do
									srcs[#srcs + 1] = ur2[k]
								end
							end
							return srcs
						end
						local NO_DEF_OPS = {
							SETTABLE = true,
							SETTABLEKS = true,
							SETTABLEN = true,
							SETGLOBAL = true,
							SETUPVAL = true,
							SETUDATAKS = true,
							RETURN = true,
							JUMP = true,
							JUMPBACK = true,
							JUMPIF = true,
							JUMPIFNOT = true,
							JUMPIFEQ = true,
							JUMPIFLE = true,
							JUMPIFLT = true,
							JUMPIFNOTEQ = true,
							JUMPIFNOTLE = true,
							JUMPIFNOTLT = true,
							JUMPXEQKNIL = true,
							JUMPXEQKB = true,
							JUMPXEQKN = true,
							JUMPXEQKS = true,
							NAMECALL = true,
							NAMECALLUDATA = true,
							CLOSEUPVALS = true,
							SETLIST = true,
							FORNLOOP = true,
							FORGLOOP = true,
							COVERAGE = true,
							CAPTURE = true,
							NOP = true,
							BREAK = true,
							PREPVARARGS = true,
							CMPPROTO = true,
							FASTCALL = true,
							FASTCALL1 = true,
							FASTCALL2 = true,
							FASTCALL2K = true,
							FASTCALL3 = true,
							JUMPX = true,
							NEWCLASSMEMBER = true,
						}
						local function getDefinedRegisters(opName, ur2, ed2)
							if NO_DEF_OPS[opName] then
								return {}
							end
							if opName == "CALL" or opName == "CALLFB" then
								local baseR = ur2[1]
								local nRes = (ed2 and ed2[2] or 1) - 1
								if nRes == -1 then
									return { baseR }
								elseif nRes == 0 then
									return {}
								end
								local defs = {}
								for k = 1, nRes do
									defs[#defs + 1] = baseR + k - 1
								end
								return defs
							end
							if opName == "GETVARARGS" then
								local baseR = ur2[1]
								local vc = (ed2 and ed2[1] or 1) - 1
								if vc == -1 then
									return { baseR }
								end
								local defs = {}
								for k = 1, vc do
									defs[#defs + 1] = baseR + k - 1
								end
								return defs
							end
							if ur2 and ur2[1] ~= nil then
								return { ur2[1] }
							end
							return {}
						end
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
						for r, tl in pairs(regGenTimeline) do
							for _, entry in ipairs(tl) do
								local defAi = entry.defAi
								local act = actions[defAi]
								if act and act.opCode then
									local opn2 = act.opCode.name
									local ed2 = act.extraData
									local name = nil
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
									elseif opn2 == "GETGLOBAL" or opn2 == "GETIMPORT" then
										local gname = constStr(ed2[1])
										if gname and KNOWN_GLOBAL_NAMES[gname] == true then
											name = gname
										end
									end
									if name then
										regInferredName[r .. ":" .. entry.gen] = name
									end
								end
							end
						end
						do
							local seenNames = {}
							for r, tl in pairs(regGenTimeline) do
								for _, entry in ipairs(tl) do
									local key = r .. ":" .. entry.gen
									local nm = regInferredName[key]
									if nm then
										if seenNames[nm] then
											regInferredName[key] = nil
										else
											seenNames[nm] = true
										end
									end
								end
							end
						end
						local regNameCache = {}
						local function fmtReg(r, instrIdx)
							if r == nil then
								return "v?"
							end
							local safeNumParams = numParams or 0
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
							local baseName = "v" .. tostring(r - safeNumParams)
							if instrIdx and regNeedsSuffix[r] then
								local g = regGenAt(r, instrIdx)
								if g > 1 then
									return baseName .. "_" .. g
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
							local emittedName = canonicalFunctionName(p.name)
							local body
							if p.name and emittedName ~= p.name then
								body =
									fmtProto(p):gsub("local function " .. p.name, "local function " .. emittedName, 1)
							else
								body = fmtProto(p)
							end
							if p.name then
								emit("" .. body)
								writeActions(registerActions[p.id])
								emit("end\n" .. fmtReg(reg, captureInstrIdx) .. " = " .. emittedName)
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
								local loopVar = numericLoopVars[r]
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
							local function handleJumps()
								local n = jumpMarkers[i]
								if n then
									jumpMarkers[i] = nil
									for _ = 1, n do
										indentLevel = math.max(0, indentLevel - 1)
										emit(ind() .. "end\n")
									end
								end
							end
							handleJumps()
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
								callBody ..= Rpre(receiverR) .. nmMethod .. "("
								if
									nArgs == -1
									and openCallTail
									and openCallTail.producer == i - 1
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
								local nextAction = actions[i + 1]
								local nextIsOpenCall = nextAction
									and nextAction.opCode
									and nextAction.opCode.name == "CALL"
									and nextAction.extraData
									and nextAction.extraData[1] == 0
								if isMultiReturn and nextIsOpenCall then
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
								local tot = ed[1] - 2
								local rb = ""
								if tot == -2 then
									rb = " " .. R(baseR) .. ", ..."
								elseif tot > -1 then
									rb = " "
									for k = 0, tot do
										rb ..= R(baseR + k)
										if k ~= tot then
											rb ..= ", "
										end
									end
								end
								emit(ind() .. "return" .. rb)
							elseif opn == "JUMP" then
								emit("-- jump to #" .. (i + ed[1]))
							elseif opn == "JUMPBACK" then
								emit(ind() .. "-- jump back to #" .. (i + ed[1] + 1))
							elseif opn == "JUMPIF" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if not " .. R(ur[1]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOT" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFEQ" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " ~= " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFLE" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " > " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFLT" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " >= " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOTEQ" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " == " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOTLE" then
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " <= " .. R(ur[2]) .. " then -- goto #" .. ei)
							elseif opn == "JUMPIFNOTLT" then
								local ei = i + ed[1]
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
								emit("end -- iterate + jump to #" .. (i + ed[1]))
							elseif opn == "FORGLOOP" then
								emit("end -- iterate + jump to #" .. (i + ed[1]))
							elseif opn == "FORGPREP_INEXT" then
								local tr = ur[1] + 1
								emit("for " .. R(tr + 2) .. ", " .. R(tr + 3) .. " in ipairs(" .. R(tr) .. ") do")
							elseif opn == "FORGPREP_NEXT" then
								local tr = ur[1] + 1
								emit("for " .. R(tr + 2) .. ", " .. R(tr + 3) .. " in pairs(" .. R(tr) .. ") do")
							elseif opn == "FORGPREP" then
								local ei = i + ed[1] + 2
								local ea = actions[ei]
								local vb = ""
								if ea then
									for k, r in ipairs(ea.usedRegisters) do
										vb ..= fmtReg(r, i)
										if k ~= #ea.usedRegisters then
											vb ..= ", "
										end
									end
								end
								emit("for " .. vb .. " in " .. R(ur[1]) .. " do -- end at #" .. ei)
							elseif opn == "GETVARARGS" then
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
								emit(ind() .. "-- jump to #" .. (i + ed[1]))
							elseif opn == "COVERAGE" then
								emit(ind() .. "-- coverage (" .. ed[1] .. ")")
							elseif opn == "JUMPXEQKNIL" then
								local rev = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
								local sign = rev and "~=" or "=="
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " " .. sign .. " nil then -- goto #" .. ei)
							elseif opn == "JUMPXEQKB" then
								local val = tostring(toBoolean(bit32.band(ed[2] or 0, 1)))
								local rev = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
								local sign = rev and "~=" or "=="
								local ei = i + ed[1]
								makeJump(ei)
								emit("if " .. R(ur[1]) .. " " .. sign .. " " .. val .. " then -- goto #" .. ei)
							elseif opn == "JUMPXEQKN" or opn == "JUMPXEQKS" then
								local cidx = bit32.band(ed[2] or 0, 0xFFFFFF)
								local val = fmtConst(consts[cidx + 1])
								local rev = bit32.rshift(ed[2] or 0, 0x1F) ~= 1
								local sign = rev and "~=" or "=="
								local ei = i + ed[1]
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
								local ei = i + (ed[1] or 0)
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
			local function manager(proceed, issue)
				if proceed then
					local startTime = os.clock()
					local result
					local ok, res = pcall(function()
						return finalize(organize())
					end)
					result = ok and res or ("-- RUNTIME ERROR:\n-- " .. tostring(res))
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
							local ind, reg, value =
								line:match("^(%s*)local%s+(v%d+_?%d*)%s*=%s*{%s*__index%s*=%s*(v%d+_?%d*)%s*}%s*$")
							if reg and value and reg == value then
								pass3b[i] = ind .. "local " .. reg .. " = {}"
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
					local seen4 = {}
					local pass4 = {}
					for _, line in ipairs(pass3b) do
						local reg = line:match("^%s*(v%d+_?%d*)%s*=")
						if reg and not seen4[reg] then
							seen4[reg] = true
							line = line:gsub("^(%s*)(v%d+_?%d*%s*=)", "%1local %2", 1)
						end
						pass4[#pass4 + 1] = line
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
	local i = 1
	while i <= #cliArgs do
		local value = cliArgs[i]
		if value == "--audit" then
			audit = true
		elseif value == "-o" or value == "--output" then
			i = i + 1
			output = cliArgs[i]
			if not output then
				error("Missing filename after -o", 0)
			end
		elseif value == "-h" or value == "--help" then
			print("Usage: luau bytecode_source_cli.lua input.luauc [-o output.lua] [--audit]")
			return
		elseif not input and type(value) == "string" and value:sub(1, 1) ~= "-" then
			input = value
		else
			error("Unknown argument: " .. tostring(value), 0)
		end
		i = i + 1
	end
	if not input then
		error("Usage: luau bytecode_source_cli.lua input.luauc [-o output.lua] [--audit]", 0)
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
	local result = ZukDecompile(bytecode)
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
