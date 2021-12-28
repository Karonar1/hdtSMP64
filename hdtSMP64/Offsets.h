#pragma once

#include <cstdint>

//function			                 1.5.97        1.6.318 	     id        1.6.323      1.6.342
//GameStepTimer_SlowTime             0x02F6B948    0x030064C8    410199    0x030064c8   0x03007708
//ArmorAttachFunction                0x001CAFB0    0x001D6740    15712     0x001d66b0   0x001d66a0
//BSFaceGenNiNode_SkinAllGeometry    0x003D87B0    0x003F08C0    26986     0x003f0830   0x003f09c0
//BSFaceGenNiNode_SkinSingleGeometry 0x003D8840    0x003F0A50    26987     0x003f09c0   0x003f0b50
//GameLoopFunction                   0x005B2FF0    0x005D9F50    36564     0x005D9CC0   0x005dae80
//GameShutdownFunction               0x01293D20    0x013B9A90    105623    0x013b99f0   0x013ba910
//TESNPC_GetFaceGeomPath             0x00363210    0x0037A240    24726     0x0037a1b0   0x0037a340
//BSFaceGenModelExtraData_BoneLimit  0x0036B4C8

namespace hdt
{
	// signatures generated with IDA SigMaker plugin
	namespace offset
	{
		// hdtSkyrimPhysicsWorld.cpp
		// 74 35 45 33 C0 33 D2
#ifdef ANNIVERSARY_EDITION
		constexpr std::uintptr_t GameStepTimer_SlowTime = 0x03007708;
#else
		constexpr std::uintptr_t GameStepTimer_SlowTime = 0x02F6B948;
#endif

		// Hooks.cpp
		// E8 ? ? ? ? 48 8B E8 FF C7 
#ifdef ANNIVERSARY_EDITION
		constexpr std::uintptr_t ArmorAttachFunction = 0x001d66a0;
#else
		constexpr std::uintptr_t ArmorAttachFunction = 0x001CAFB0;
#endif

		// BSFaceGenNiNode last vfunc
#ifdef ANNIVERSARY_EDITION
		constexpr std::uintptr_t BSFaceGenNiNode_SkinAllGeometry = 0x003f09c0;
		constexpr std::uintptr_t BSFaceGenNiNode_SkinSingleGeometry = 0x003f0b50;
#else
		constexpr std::uintptr_t BSFaceGenNiNode_SkinAllGeometry = 0x003D87B0;
		constexpr std::uintptr_t BSFaceGenNiNode_SkinSingleGeometry = 0x003D8840;
#endif
		// .text:00000001403D88D4                 cmp     ebx, 8
		// patch 8 -> 7
		constexpr std::uintptr_t BSFaceGenNiNode_SkinSingleGeometry_bug = BSFaceGenNiNode_SkinSingleGeometry + 0x96;

		// Hooks.cpp
		// function responsible for majority of main game thread loop
#ifdef ANNIVERSARY_EDITION
		// E8 ? ? ? ? 84 DB 74 24 
		constexpr std::uintptr_t GameLoopFunction = 0x005dae80;
		// E8 ? ? ? ? E8 ? ? ? ? E8 ? ? ? ? 48 8B 0D ? ? ? ? 48 85 C9 74 0C E8 ? ? ? ? 
		constexpr std::uintptr_t GameShutdownFunction = 0x013ba910;
#else
		// E8 ? ? ? ? 84 DB 74 24 
		constexpr std::uintptr_t GameLoopFunction = 0x005B2FF0;
		// E8 ? ? ? ? E8 ? ? ? ? E8 ? ? ? ? 48 8B 0D ? ? ? ? 48 85 C9 74 0C E8 ? ? ? ? 
		constexpr std::uintptr_t GameShutdownFunction = 0x01293D20;
#endif

		// FaceGeom string
#ifdef ANNIVERSARY_EDITION
		constexpr std::uintptr_t TESNPC_GetFaceGeomPath = 0x0037a340;
#else
		constexpr std::uintptr_t TESNPC_GetFaceGeomPath = 0x00363210;
#endif

		// BSFaceGenModelExtraData Bone Limit
		// 8B 70 58 EB 02 
		constexpr std::uintptr_t BSFaceGenModelExtraData_BoneLimit = 0x0036B4C8;
	}
}
