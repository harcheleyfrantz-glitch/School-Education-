package com.rodwave.engine.elf

import com.rodwave.engine.compat.NativeModInspector
import com.rodwave.engine.scm.Abi
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ElfFileTest {

    @Test
    fun readsArm32AndArm64Libraries() {
        val arm32 = ElfFile.parse(ElfBuilder.build(false, ElfFile.EM_ARM, exports = listOf("__GetModInfo", "OnModLoad"), needed = listOf("liblog.so"), rodata = listOf("net.example.mod")))
        assertEquals(Abi.ARMEABI_V7A, arm32.abi)
        assertFalse(arm32.is64Bit)
        assertTrue(arm32.isSharedObject)
        assertTrue(arm32.exports("__GetModInfo"))
        assertEquals(listOf("liblog.so"), arm32.neededLibraries)
        assertTrue("net.example.mod" in arm32.readOnlyStrings())

        val arm64 = ElfFile.parse(ElfBuilder.build(true, ElfFile.EM_AARCH64, exports = listOf("JNI_OnLoad")))
        assertEquals(Abi.ARM64_V8A, arm64.abi)
        assertTrue(arm64.is64Bit)
        assertEquals(listOf("JNI_OnLoad"), arm64.exportedSymbols)
        assertFalse(arm64.exports("__GetModInfo"))
    }

    @Test
    fun inspectorRecognisesAmlMods() {
        val mod = NativeModInspector.inspect(
            "libCLEOMod.so",
            ElfBuilder.amlMod(abi64 = true, guid = "net.rusjj.cleolib", extraStrings = listOf("com.rockstargames.gtasa", "android.app.Activity")),
        )
        assertTrue(mod.isAmlMod)
        assertEquals(Abi.ARM64_V8A, mod.abi)
        assertEquals(listOf("OnModLoad"), mod.amlCallbacks)
        assertTrue(mod.mentionsGtaSa)
        assertTrue("net.rusjj.cleolib" in mod.guidCandidates)
        assertFalse("com.rockstargames.gtasa" in mod.guidCandidates)

        val notMod = NativeModInspector.inspect("libfoo.so", ElfBuilder.build(true, ElfFile.EM_AARCH64, exports = listOf("foo")))
        assertFalse(notMod.isAmlMod)
        val x86 = NativeModInspector.inspect("libx.so", ElfBuilder.build(false, ElfFile.EM_386, exports = listOf("__GetModInfo")))
        assertEquals(Abi.X86, x86.abi)
        assertFalse(x86.isLoaderCompatibleAbi)
        val text = NativeModInspector.inspect("readme.so", "hello".toByteArray())
        assertFalse(text.isElf)
    }

    @Test
    fun rejectsMalformedFilesWithoutCrashing() {
        assertFailsWith<ElfException> { ElfFile.parse(ByteArray(10)) }
        assertFailsWith<ElfException> { ElfFile.parse("not an elf file at all, sorry......................................".toByteArray()) }
        val good = ElfBuilder.build(true, ElfFile.EM_AARCH64, exports = listOf("__GetModInfo"))
        // Section table pointing outside the file.
        val broken = good.copyOf()
        broken[40] = 0x7F; broken[41] = 0x7F; broken[42] = 0x7F
        assertFailsWith<ElfException> { ElfFile.parse(broken) }
        // Random mutations must only ever produce ElfException.
        val random = Random(99)
        repeat(2_000) {
            val m = good.copyOf(random.nextInt(4, good.size + 1))
            repeat(random.nextInt(1, 6)) { m[random.nextInt(m.size)] = random.nextInt(256).toByte() }
            try {
                ElfFile.parse(m)
            } catch (_: ElfException) {
            }
            NativeModInspector.inspect("fuzz.so", m)
        }
    }
}
