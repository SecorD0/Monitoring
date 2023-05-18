# Changelog

### 18.05.2023
- Prevent the script stucking because of the `solana vote-account ... --with-rewards` command stucking.

### 05.07.2022
- If script can't get a stake reward for the last epoch, it counts as zero.

### 08.06.2022
- If it failed to get the size of the block reward, it sets the average value from the DB.

### 06.05.2022
- Fixed a bug with the editing of awards for the previous epoch.

### 05.05.2022
- The algorithm for determining `Syncing` status was changed;
- Epoch information is now taken from the global RPC (higher accuracy of epoch end time);
- A few cosmetic changes to the script.
