@echo off
title Join AEGIS Chernarus (with @AEGIS_Pricing)
cd /d "E:\SteamLibrary\steamapps\common\DayZ"
set MODS=!Workshop\@Dabs Framework;!Workshop\@CF;!Workshop\@DayZ-Expansion-Core;!Workshop\@DayZ-Expansion-Licensed;!Workshop\@DayZ-Expansion-Vehicles;!Workshop\@DayZ-Expansion-AI;!Workshop\@DayZ-Expansion-Market;!Workshop\@DayZ-Expansion-Bundle;!Workshop\@DayZ-Expansion-Weapons;!Workshop\@DayZ-Expansion-Quests;!Workshop\@WindstridesClothingPack;!Workshop\@Alevaric's Clothing Overhaul;!Workshop\@[Remastered] Arma Weapon Pack;!Workshop\@AI War Zones;!Workshop\@VPPAdminTools;!Workshop\@RedFalcon Flight System Heliz;!Workshop\@Blackouts Custom ATM;!Workshop\@SimpleTraderSigns_Expansion;!Workshop\@MMG - Mightys Military Gear;!Workshop\@Paragon Gear and Armor;@AEGIS_Pricing
start "" "DayZ_BE.exe" -exe DayZ_x64.exe "-mod=%MODS%" -connect=157.85.86.5 -port=2302 -name=Yodatech
