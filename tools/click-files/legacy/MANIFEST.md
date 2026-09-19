# Legacy click-files (unreviewed backup copies)

**These are unreviewed legacy copies, NOT approved to run. Kept only for backup.** They were found
unversioned at the top level of the owner's `GitHub\` folder (`AEGIS-*.cmd` / `AEGIS-*.ps1`), existing
only on one disk (plan item 2.6). Bytes and line endings are preserved unedited. None was run or edited.

Scan: no gitleaks on the host; a manual pattern scan (passwords, tokens, keys, private-key blocks,
bearer/authorization, connection strings, -Credential, emails, phone numbers, Steam64 ids, DPAPI blobs,
webhook URLs, long high-entropy literals) found no plausible secret. Noted, not failed: absolute paths
containing the local Windows username; public VPS/game-server IPs without credentials (40.160.90.128 in
several files, 157.85.86.5 in AEGIS-Join-Chernarus.cmd with the in-game handle); the owner's first name in
one prompt string (AEGIS-Security-Docs-Saturday.cmd).

Set aside (never touched): the *.RETIRED.cmd.disabled files, logs, json, orig, md.
Files whose name exists in MasterThread with different content were NOT copied (no overwrite).

| file | SHA-256 (raw bytes) | size | status |
|---|---|---|---|
| AEGIS-Allow-PM-Seat-Tools.cmd | eff21713863b17549974c1eeb267b280a47e7c113e7de5ebb83f0802201826f2 | 1195 | copied |
| AEGIS-Allow-Seat-Merge.cmd | 690a4b652f6d8173ff84236b42ea05cbaefdb9d1d5f25ba507cb34a5593b6efb | 2150 | copied |
| AEGIS-Deploy-Website.cmd | 2b08f4f06f414189ed41960cb83a2c673bce32d1184882dc6f0f5474f0be9b48 | 1932 | copied |
| AEGIS-Fix-Runner-Unzip.cmd | 6b1b6178f45f731f2ad6edca8406f2e229a38c133e4b187f36818462fe6c24e9 | 2235 | copied |
| AEGIS-Fleet-Wallboard.cmd | cd804f5ada8d62d6bdc3944755a212d5f46320297ff63c2d8021bf15131fb3fa | 974 | copied |
| AEGIS-Flip-Actions-Token-4-Repos.cmd | 925cc5ca189213331fa6946f6e3010fef48c3fbf305501e16327ece0d3c4f119 | 978 | copied |
| AEGIS-Import-App-Key.cmd | d736605cbf109098c515236190d728f285ec65d5de20cc56030cf45ec1710d0e | 962 | copied |
| AEGIS-Join-Chernarus.cmd | 27f8ec78e0545b4e1b0811e6c3df29925d818f93c43a39b5ec918da2bc681979 | 884 | copied |
| AEGIS-Key-1-Discord-Webhooks.cmd | 96a5e5441bd97db5c004c28c70f87c4ddc96af0bc4dd535906bfebfa46848f49 | 824 | copied |
| AEGIS-Key-2-Admin-Bot.cmd | 4a92120269c4ff090f9c6c9a88e484fda7db5c3c0ac58fa870bc06141c6c7e8b | 180 | copied |
| AEGIS-Key-3-Discord-Community-Bot.cmd | 1333eec9a21c5f5c6b4eb40fb0bf0d6ef4219856f6977ec8b8cbac902325e514 | 158 | copied |
| AEGIS-Key-4-GitHub-2FA-Recovery.cmd | 3f31f09c1b7ac59bdbf99fbdcfa573958e5283336e8a842f0d532de85bb37d66 | 172 | copied |
| AEGIS-Key-5-Rotation-Anthropic.cmd | 25a5b416aace143e8cd152e44f21951bd652488983b90b2ac6fdb0453f49093a | 149 | copied |
| AEGIS-Key-6-Rotation-Cloudflare.cmd | 40605120e69438fd00be4871af8f814e34e6849057d0eab3a84e2d1aa623d926 | 150 | copied |
| AEGIS-Key-7-Rotation-OVH.cmd | 1bcf24006d6668cf1b257d78ca8a1ed1112beb604dec3f58ab821395b380033a | 143 | copied |
| AEGIS-Key-8-Rotation-Discord.cmd | 9adfe56ddde35b139dbb731a44c09ebe4c7b457bc93268ba4c123c29e72ea3ee | 157 | copied |
| AEGIS-Key-9-Rotation-Discord-Admin.cmd | e00ea9b5b50e0bb051e0e61b76a75429f5629dac4813011baba86e3ce384044a | 153 | copied |
| AEGIS-Merge-Queue.cmd | 013b944e6f912fcb668f9ea4b92e75b42911f6441c2bbf0035ac55b9a06eb73a | 1290 | copied |
| AEGIS-Narrow-Local-Allowlist.cmd | 9e070e2f06ad08d12aa89c939be61bf2bacfca6cc91f49144cac823e0e3ccccd | 1791 | copied |
| AEGIS-Protect-Default-Branches.cmd | f58d5bfedcadab2b88cefa996a613f08c71b93fb6a5c02fd2ff4f564b59aa2f8 | 1217 | copied |
| AEGIS-Prove-App-Review.cmd | ce71e8cede4bd6db4242744d205fbc1f8c13c117c9553de5c9eedaa4d7139879 | 961 | skipped-identical |
| AEGIS-Push-Agent-Roster-Backup.cmd | dc58942de6cc026e3bd72942aa8259cfc019797da60725cd0f72be965becfc1c | 6332 | skipped-identical |
| AEGIS-Register-L1Pilot.cmd | dc26333feadc1a81e40ce0c2928ef732ade2e813e40e4dbfcedbe9de9ef70a44 | 1712 | copied |
| AEGIS-Register-PmHeartbeat-Watchdog.cmd | 974553517789fdf566cd5f911fed013b1fc650ce1177876e3e47332b0d7bc1e4 | 1642 | copied |
| AEGIS-Remove-6-Verified-Worktrees.cmd | 3005df184abefdb4b52825b824e337ad122a0db182fa7991657adbe7128b6faa | 1945 | copied |
| AEGIS-Require-Passing-Checks.cmd | f6723da475242a86431e635cb84060ed8e9f1971c3902b4dd3f92c756bc0b85b | 1063 | differs-not-copied |
| AEGIS-Restore-Passing-Checks.cmd | 0534ca4df445ef3d8a24ef2a020a027c6b43d789fdbd9e45aeec0603acd95a61 | 535 | skipped-identical |
| AEGIS-Security-Docs-Saturday.cmd | 95e8fc9b8751edbbf901d87292f6eee7a161030ba660dad6a67b3bdadcfa919e | 1299 | copied |
| AEGIS-Unregister-L1Pilot.cmd | ea184940888a8bbdcf4d4258149a804454fbbab278844b5be11dc3cf38b0a4c1 | 607 | copied |
| AEGIS-Unregister-PmHeartbeat-Watchdog.cmd | 66568543947a1151e2a31e5b479d06354375ac3defad16ab0b24231f0c87caa0 | 626 | copied |
| AEGIS-VPS-CI-All.cmd | d08792cf871ec5d0695e9139611e4e5344fa3a663f20b57c513684c18e8b4dff | 720 | copied |
| AEGIS-VPS-Economy-Sync.cmd | c74bde3a75a7aa49d50dfc215bee304310277c44bac261bc8b268cac7fc5a66a | 555 | copied |
| AEGIS-VPS-Finish.cmd | eebb434125e3f804209ab380cd4c9fcfafa2f4d6e9cdaaaeffa5d985026f6d98 | 94 | copied |
| AEGIS-Allow-PM-Seat-Tools.ps1 | 1a723ca1b3aaada2b60e65c69790a30c4dfb3b11abf87839f1c893a9bc3958da | 15931 | copied |
| AEGIS-Allow-Seat-Merge.ps1 | 1c3ecf6c7b0bf57ee9428ac0ceeecd725c85956b94b0a9777d187ccc143596da | 23754 | copied |
| AEGIS-Deploy-Website.ps1 | e544e78191674dcf81b6144b231d484d89da155950bb50ae3e126fb3b3b2ec77 | 17404 | copied |
| AEGIS-Flip-Actions-Token-4-Repos.ps1 | 896c20f1ef84dd48061f27d3e76b389a35a54381f902addfa0eed6f41622ca30 | 4128 | copied |
| AEGIS-Key-Rotation-Session.ps1 | 4e08f43bfc3f4fcbd396f4d893774ba4fa45c162873f2b9e22239c16ab172510 | 6933 | copied |
| AEGIS-Merge-Queue.ps1 | 4dea1b7ce526dad48efe043b32e9921d9e7469fd4fa0e92544bd971b631d6635 | 18551 | differs-not-copied |
| AEGIS-Narrow-Local-Allowlist.ps1 | 7ad094e1a1fed5ce63d97e2ce35b9f306e87b136f6e9e27bb8efe97416a74b99 | 25340 | copied |
| AEGIS-Protect-Default-Branches.ps1 | 13c75c7c6f9844bb30b6a643e04f19a492e1747fed5a42a340c02ba1bba7af7c | 12475 | copied |
| AEGIS-Prove-App-Review.ps1 | ed27e1d995d6829c5351cb29c8897c3edd0181b45459866a68ede63e43d6b280 | 29597 | skipped-identical |
| AEGIS-Register-L1Pilot.ps1 | 0f4700c546188806283ecde8f350f4437ecca8c9bd9ee4e3956da1fc7a6bbe1e | 29612 | copied |
| AEGIS-Register-PmHeartbeat-Watchdog.ps1 | 1e281cb65c9471a0dae6da48d020c3918dd015b7a552aa0f3cf228c6c0c935d3 | 28539 | copied |
| AEGIS-Require-Passing-Checks.ps1 | 7cb208d114badfbb3a4d9ad3380ee5ded5053c1c6011725f0c857ce6bf32ef36 | 29649 | differs-not-copied |
| AEGIS-Unregister-L1Pilot.ps1 | ff662294022b70874883ad7b6acc41903948e3d6bfb65da4c92307398e3c36ac | 6288 | copied |
| AEGIS-Unregister-PmHeartbeat-Watchdog.ps1 | d07186f495d072c7c781344574ad44e00cb4ef014b46b46b018efe2aaa36be25 | 2645 | copied |
| AEGIS-VPS-CI-All-Launcher.ps1 | e19ef06786d00cce54a5127759150daad5f9db9a977e847e0fe92e0305aa5031 | 6926 | copied |
| AEGIS-VPS-Economy-Sync.ps1 | a73cb4cbfe4cbc1466ab66cadc76886e580dd780036b371f38c0fdcbefb7093b | 4085 | copied |
| AEGIS-VPS-Finish.ps1 | 76108fd3f517f47df38e79576220b629df3ab5a356187be8badb45b3887f203b | 3427 | copied |
