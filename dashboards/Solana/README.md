# Changelog

### 19.02.2024
- Replaced the alias of the binary file with the full path in one of the commands.

### 27.09.2023
- The table of rewards in the output of the `solana vote-account` command has been changed. The parsing logic of this data has been updated.

### 18.05.2023
- Prevent the script stucking because of the `solana vote-account ... --with-rewards` command stucking.

### 05.07.2022
- If script can't get a stake reward for the last epoch, it counts as zero.

### 08.06.2022
- If it failed to get the size of the block reward, it sets the average value from the DB.

### 06.05.2022
- Fixed a bug with the editing of rewards for the previous epoch.

### 05.05.2022
- The algorithm for determining `Syncing` status was changed;
- Epoch information is now taken from the global RPC (higher accuracy of epoch end time);
- A few cosmetic changes to the script.
