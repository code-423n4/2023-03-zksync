# ✨ So you want to sponsor a contest

This `README.md` contains a set of checklists for our contest collaboration.

Your contest will use two repos: 
- **a _contest_ repo** (this one), which is used for scoping your contest and for providing information to contestants (wardens)
- **a _findings_ repo**, where issues are submitted (shared with you after the contest) 

Ultimately, when we launch the contest, this contest repo will be made public and will contain the smart contracts to be reviewed and all the information needed for contest participants. The findings repo will be made public after the contest report is published and your team has mitigated the identified issues.

Some of the checklists in this doc are for **C4 (🐺)** and some of them are for **you as the contest sponsor (⭐️)**.

---

# Contest setup

# Repo setup

## ⭐️ Sponsor: Add code to this repo

- [ ] Create a PR to this repo with the below changes:
- [ ] Provide a self-contained repository with working commands that will build (at least) all in-scope contracts, and commands that will run tests producing gas reports for the relevant contracts.
- [ ] Make sure your code is thoroughly commented using the [NatSpec format](https://docs.soliditylang.org/en/v0.5.10/natspec-format.html#natspec-format).
- [ ] Please have final versions of contracts and documentation added/updated in this repo **no less than 24 hours prior to contest start time.**
- [ ] Be prepared for a 🚨code freeze🚨 for the duration of the contest — important because it establishes a level playing field. We want to ensure everyone's looking at the same code, no matter when they look during the contest. (Note: this includes your own repo, since a PR can leak alpha to our wardens!)


---

## ⭐️ Sponsor: Edit this README

Under "SPONSORS ADD INFO HERE" heading below, include the following:

- [ ] Modify the bottom of this `README.md` file to describe how your code is supposed to work with links to any relevent documentation and any other criteria/details that the C4 Wardens should keep in mind when reviewing. ([Here's a well-constructed example.](https://github.com/code-423n4/2022-08-foundation#readme))
  - [ ] When linking, please provide all links as full absolute links versus relative links
  - [ ] All information should be provided in markdown format (HTML does not render on Code4rena.com)
- [ ] Under the "Scope" heading, provide the name of each contract and:
  - [ ] source lines of code (excluding blank lines and comments) in each
  - [ ] external contracts called in each
  - [ ] libraries used in each
- [ ] Describe any novel or unique curve logic or mathematical models implemented in the contracts
- [ ] Does the token conform to the ERC-20 standard? In what specific ways does it differ?
- [ ] Describe anything else that adds any special logic that makes your approach unique
- [ ] Identify any areas of specific concern in reviewing the code
- [ ] Optional / nice to have: pre-record a high-level overview of your protocol (not just specific smart contract functions). This saves wardens a lot of time wading through documentation.
- [ ] See also: [this checklist in Notion](https://code4rena.notion.site/Key-info-for-Code4rena-sponsors-f60764c4c4574bbf8e7a6dbd72cc49b4#0cafa01e6201462e9f78677a39e09746)
- [ ] Delete this checklist and all text above the line below when you're ready.

---

# zkSync era System Contracts contest details
- Total Prize Pool: $165,000 USDC
  - HM awards: $127,500 USDC 
  - QA report awards: $15,000 USDC
  - Gas report awards: $7,500 USDC 
  - Judge + presort awards: $30,000 USDC 
  - Scout awards: $500 USDC 
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-03-zksync-era-system-contracts-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts March 10, 2023 20:00 UTC
- Ends March 19, 2023 20:00 UTC

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](add link to report) within an hour of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

[ ⭐️ SPONSORS ADD INFO HERE ]

# Overview

## System contracts/bootloader description (VM v1.3.0)

### Introduction

#### Bootloader

On standard Ethereum clients, the workflow for executing blocks is the following:

1. Pick a transaction, validate the transactions & charge the fee, execute it
2. Gather the state changes (if the transaction has not reverted), apply them to the state. 
3. Go back to step (1) if the block gas limit has not been yet exceeded.

However, having such flow on zkSync (i.e. processing transaction one-by-one) would be too inefficient, since we have to run the entire proving workflow for each individual transaction. That's what we need the *bootloader* for: instead of running N transactions separately, we run the entire block as a single program that accepts the array of transactions as well as some other block metadata and processes them inside a single big "transaction". The easiest way to think about the bootloader is to think in terms of EntryPoint from EIP4337: it also accepts the array of transactions and facilitates the Account Abstraction protocol.

The hash of the code of the bootloader is stored on L1 and can only be changed as a part of a system upgrade. Note, that unlike system contracts, the bootloader's code is not stored anywhere on L2. That's why we may sometimes refer to the bootloader's address as formal. It only exists for the sake of providing some value to `this`/`msg.sender`/etc. When someone calls the bootloader address (e.g. to pay fees) the [EmptyContract's](#empty-contracts) code is actually invoked.

#### System contracts

While most of the primitive EVM opcodes can be supported out of the box (i.e. zero-value calls, addition/multiplication/memory/storage management, etc), some of the opcodes are not supported by the VM by default and they are implemented via "system contracts" — these contracts are located in a special *kernel space*, i.e. in the address space in range (0..2^16-1), and they have some special privileges, which users' contracts don't have. These contracts are pre-deployed at the genesis and updating their code can be done only via system upgrade, managed from L1.

The use of each system contract will be explained down below.

### zkEVM internals

Full specification of the zkEVM is beyond the scope of this document. However, this section will give you most of the details needed for understanding the L2 system smart contracts & basic differences between EVM and zkEVM.

### Registers and memory management

On EVM, during transactions execution, the following memory areas are available:

- `memory` itself.
- `calldata` the immutable slice of parent memory.
- `returndata` the immutable slice returned by the latest call to another contract.
- `stack` where the local variables are stored.

Unlike EVM, which is stack machine, zkEVM has 16 registers. Instead of receiving input from `calldata`, zkEVM starts by receiving a *pointer* in its first register (basically a packed struct with 4 elements: the memory page id, start and length of the slice to which it points to) to the calldata page of the parent. Similarly, a transaction can receive some other additional data within its registers at the start of the program: whether the transaction should invoke the constructor, whether the transaction has `isSystem` flag, etc. The meaning of each of these flags will be expanded further in this section.

*Pointers* are separate type in the VM. It is only possible to:

- Read some value within a pointer.
- Shrink the pointer by reducing the slice to which pointer points to.
- Receive the pointer to the returndata/as a calldata.
- Pointers can be stored only on stack/registers to make sure that the other contracts can not read memory/returndata of contracts they are not supposed to.
- A pointer can be converted to the u256 integer representing it, but an integer can not be converted to a pointer to prevent unallowed memory access.
- It is not possible to return a pointer that points to a memory page with id smaller than the one for the current page. What this means is that it is only possible to use only pointer to the memory of the current frame or one of the pointers returned by the subcalls of the current frame.

#### Memory areas in zkEVM

For each frame, the following memory areas are allocated:

- *Heap* (plays the same role as `memory` on Ethereum).
- *AuxHeap* (auxiliary heap). It has the same properties as Heap, but it is used for the compiler to encode calldata/copy the returndata from the calls to system contracts to not interfere with the standard Solidity memory alignment.
- *Stack*. Unlike, Ethereum, stack is not the primary place to get arguments for opcodes. The biggest difference between stack on zkEVM and EVM is that on zkSync stack can be accessed at any location (just like memory). While users do not pay for the growth of stack, the stack can be fully cleared at the end of the frame, so the overhead is minimal.
- *Code*. The memory area from which the VM executes the code of the contract. The contract itself can not read the code page, it is only done implicitly by the VM.

Also, as mentioned in the previous section, the contract receives the pointer to the calldata. 

#### Managing returndata & calldata

Whenever a contract finishes its execution, the parent's frame receives a *pointer* as `returndata`. This pointer may point to the child frame's heap/auxHeap or it can even be the same `returndata` pointer that the child frame received from some of its child frames.

The same goes with the `calldata`. Whenever a contract starts its execution, it receives the pointer to the calldata. The parent frame can provide any valid pointer as the calldata, which means it can either be a pointer to the slice of parent's frame memory (heap or auxHeap) or it can be some valid pointer that the parent frame has received before as calldata/returndata.

Contracts simply remeber the calldata pointer at the start of the execution frame (it is by design of the compiler) and remembers the latest received returndata pointer.

Some important implications of this is that it is now possible to do the following calls without any memory copying:

A → B → C

where C receives a slice of the calldata received by B.

The same goes for returning data:

A ← B ← C

There is no need to copy returned data if the B returns a slice of the returndata returned by C.

Note, that you can *not* use the pointer that you received as calldata as returndata (i.e. return it at the end of the execution frame). Otherwise, it would be possible that returndata points to the memory slice of the active frame and allow editing the `returndata`. It means that in the examples above, C could not return a slice of its calldata without memory copying.

These memory optimizations have not been utilized yet by the compiler.

#### Returndata & precompiles

Some of the operations which are opcodes on Ethereum, have become calls to some of the system contracts. Most notable examples are Keccak256, SystemContext, etc. Note, that, if done naively, the following lines of code would work differently on zkSync and Ethereum:

```solidity
pop(call(...))
let x = keccak(...)
returndatacopy(...)
```

Since the call to keccak precompile would modify the `returndata`. To avoid this, our compiler does not override the latest `returndata` pointer after calls to such opcode-like precompiles. 

### zkSync specific opcodes

While some Ethereum opcodes are not supported out of the box, some of the new opcodes were added to facilitate the development of the system contracts.

Note, that this lists does not aim to be specific about the internals, but rather explain methods in the `SystemContractHelper.sol`

#### **Only for kernel space**

These opcodes are allowed only for contracts in kernel space (i.e. system contracts). If executed in other places they result in `revert(0,0)`.

- `mimic_call`. The same as a normal `call`, but it can alter the `msg.sender` field of the transaction.
- `to_l1`. Sends a raw L2→L1 log to Ethereum. The structure of this log can be seen [here](https://github.com/matter-labs/era-contracts/blob/main/ethereum/contracts/zksync/Storage.sol#L44).
- `event`. Emits an L2 log to zkSync. Note, that L2 logs are not equivalent to Ethereum events. Each L2 log can emit 64 bytes of data (the actual size is 88 bytes, because it includes the emitter address, etc). A single Ethereum event is represented with multiple `event` logs. This opcode is only used by `EventWriter` system contract.
- `precompile_call`. This is an opcode that accepts two parameters: the uint256 representing the packed parameters for it as well as the gas to burn. Besides the price for the precompile call itself, it burns the provided gas and executes the precompile. The action that it does depend on `this` during execution:
- If it is the address of the `ecrecover` system contract, it performs the ecrecover operation
- If it is the address of the `sha256`/`keccak256` system contracts, it performs the corresponding hashing operation.
- It does nothing (i.e. just burns gas) otherwise. It can be used to burn gas needed for L2→L1 communication or publication of bytecodes onchain.
- `setValueForNextFarCall` sets `msg.value` for the next `call`/`mimic_call`. Note, that it does not mean that the value will be really transferred. It just sets the corresponding `msg.value` context variable. The transferring of ETH should be done via other means by the system contract that uses this parameter.
Note, that this method has no effect on `delegatecall` , since `delegatecall` inherits the `msg.value` of the previous frame.
- `increment_tx_counter` increments the counter of the transactions within the VM. The transaction counter used mostly for the VM's internal tracking of events. Used only in bootloader after the end of each transaction.
- `set_pubdata_price` sets the price (in gas) for publishing a single byte of pubdata.

#### **Generally accessible**

Here are opcodes that can be generally accessed by any contract. Note that while the VM allows to access these methods, it does not mean that this is easy: the compiler might not have convenient support for some use-cases yet. 

- `near_call`. It is basically a "framed" jump to some location of the code of your contract. The difference between the near_call and ordinary jump are:
1) It is possible to provide an gasLimit for it
2) If the near call frame panics, all state changes made by it are reversed. Please note, that the memory changes will **not** be reverted.
- `getMeta`. Returns an u256 packed value of [ZkSyncMeta](https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/SystemContractHelper.sol#L16) struct. Note that this is not tight packing. The struct is formed by the [following rust code](https://github.com/matter-labs/era-zkevm_opcode_defs/blob/main/src/definitions/abi/meta.rs#L14).
- `getCodeAddress` — receives the address of the executed code. This is different from `this` , since in case of delegatecalls `this` is preserved, but `codeAddress` is not.

#### Flags for calls

Besides the calldata, it is also possible to provide additional information to the callee when doing `call` , `mimic_call`, `delegate_call`. The called contract will receive the following information in its first 12 registers at the start of execution:

- *r1* — the pointer to the calldata.
- *r2* — the pointer with flags of the call. This is a mask, where each bit is set only if certain flags have been set to the call. Currently, two flags are supported:
0-bit: `isConstructor` flag. This flag can only be set by system contracts and denotes whether the account should execute its constructor logic. Note, unlike Ethereum, there is no separation on constructor & deployment bytecode.
1-bit: `isSystem` flag. Whether the call intends a system contracts' function. While most of the system contracts' functions are relatively harmless, accessing some with calldata only may break the invariants of Ethereum, e.g. if the system contract uses `mimic_call`: no one expects that by calling a contract some operations may be done out of the name of the caller. This flag can be only set if the callee is in kernel space.
- The rest r3..r12 registers are non-empty only if the `isSystem` flag is set. There may be arbitrary values passed.

The compiler implementation is that these flags are remembered by the contract and can be accessed later during execution via special [simulations](#simulations-via-our-compiler).

If the caller provides inappropriate flags (i.e. tries to set `isSystem` flag when callee is not in the kernel space), the flags are ignored.

#### `onlySystemCall` modifier

Some of the system contracts can act on behalf of the user or have a very important impact on the behavior of the account. That's why we wanted to make it clear that users can not invoke potentially dangerous operations by doing a simple EVM-like `call`. Whenever a user wants to invoke some of the operations which we considered dangerous, they must explicitly provide `isSystem` flag with them.

The `onlySystemCall` flag checks that the call was either done with the `isSystemCall` flag provided or the call is done by another system contract (since Matter Labs is fully aware of system contracts).

#### Simulations via our compiler

In the future, we plan to introduce our "extended" version of Solidity with more supported opcodes than the original one. However, right now it was beyond the capacity of the team to do, so in order to represent accessing zkSync-specific opcodes, we use `call` opcode with certain constant parameters that will be automatically replaced by the compiler with zkEVM native opcode.

Example:

```solidity
function getCodeAddress() internal view returns (address addr) {
    address callAddr = CODE_ADDRESS_CALL_ADDRESS;
    assembly {
        addr := staticcall(0, callAddr, 0, 0xFFFF, 0, 0)
    }
}
```

In the example above, the compiler will detect that the static call is done to the constant `CODE_ADDRESS_CALL_ADDRESS` and so it will replace it with the opcode for getting the code address of the current execution.

Full list of opcode simulations can be found here:

[https://www.notion.so/matterlabs/VM-specific-v1-3-0-opcodes-simulation-ca97fa8cb1a7492daa21178c6df2a793](https://www.notion.so/VM-specific-v1-3-0-opcodes-simulation-ca97fa8cb1a7492daa21178c6df2a793)

We also use verbatim-like statements to access zkSync-specific opcodes in the bootloader:

[https://www.notion.so/matterlabs/VM-specific-v1-2-0-opcodes-simulation-verbatim-a641281b39e740c296a99cd6d238d90a](https://www.notion.so/VM-specific-v1-3-0-opcodes-simulation-verbatim-fbe4be0122a640ff9a9e8d3973c75490)

All the usages of the simulations in our Solidity code are implemented in these two files:

- [https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/SystemContractHelper.sol](https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/SystemContractHelper.sol)
- [https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/SystemContractsCaller.sol](https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/SystemContractsCaller.sol)

All usages in Yul code are a part of the bootloader implementation

**Simulating** `near_call` **(in Yul only)**

In order to use `near_call` i.e. to call a local function, while providing a limit of gas that this function can use, the following syntax is used:

The function's name should contain `ZKSYNC_NEAR_CALL` string in its name and accept at least 1 input parameter. The first input parameter is the packed ABI of the `near_call`. Currently, it is equal to the number of gas to be passed with the `near_call`.

Whenever a `near_call` panics, the `ZKSYNC_CATCH_NEAR_CALL` function is called.

*Important note:* the compiler behaves in a way that if there is a `revert` in the bootloader, the `ZKSYNC_CATCH_NEAR_CALL` is not called and the parent frame is reverted as well. The only way to revert only the `near_call` frame is to trigger VM's *panic* (it can be triggered with either invalid opcode or out of gas error).

*Important note 2:* The 63/64 rule does not apply to `near_call`.

**Notes on security**

To prevent unintended substitution, the compiler will require `--is-system` flag to be passed during compilation for the above substitutions to work.

### Bytecode hashes

On zkSync the bytecode hashes are stored in the following format:

- The 0th byte denotes the version of the format. Currently the only version that is used is "1".
- The 1st byte is `0` for deployed contracts' code and `1` for the contract code that is being constructed.
- The 2nd and 3rd bytes denote the length of the contract in 32-byte words as big-endian 2-byte number.
- The next 28 bytes are the last 28 bytes of the sha256 hash of the contract's bytecode.

The bytes are ordered in little-endian order (i.e. the same way as for `bytes32`).

#### Bytecode validity

A bytecode is valid if it:

- Has its length in bytes divisible by 32 (i.e. consists of an integer number of 32-byte words).
- Has a length of less than 2^16 words (i.e. its length fits into 2 bytes).
- Has an odd length in words (i.e. the 3th byte is an odd number).

Note, that it does not have to consist of only correct opcodes. In case the VM encounters an invalid opcode, it will simply revert (similar to how EVM would treat them).

A call to a contract with invalid bytecode can not be proven. That is why it is **essential** that no contract with invalid bytecode is ever deployed on zkSync. It is the job of the [KnownCodesStorage](#knowncodestorage) to ensure that all allowed bytecodes in the system are valid.

## Account abstraction

One of the other important features of zkSync is the support of account abstraction. It is highly recommended to read the documentation on our AA protocol here: [https://v2-docs.zksync.io/dev/developer-guides/aa.html#introduction](https://v2-docs.zksync.io/dev/developer-guides/aa.html#introduction).

### Features included in the audit

While the description above gives an overview of zkSync account abstraction functionality, there are some changes introduced before the audit that are not available on testnet (and thus not reflected in the documentation above).

#### Refactoring in method naming

The methods have absolutely the same role & functionality, the only difference is naming.

`prePaymaster` → `prepareForPaymaster` 

`postOp` → `postTransaction`

#### Account versioning

Now, each account can also specify which version of the account abstraction protocol do they support. This is needed to allow breaking changes of the protocol in the future.

Currently, two versions are supported: `None` (i.e. it is a simple contract and it should never be used as `from` field of a transaction), and `Version1`.

#### Nonce ordering

Accounts can also signal to the operator which nonce ordering it should expect from these accounts: `Sequential` or `Arbitrary`. 

`Sequential` means that the nonces should be ordered in the same way as in EOAs. This means, that, for instance, the operator will always wait for a transaction with nonce `X` before processing a transaction with nonce `X+1`.

`Arbitrary` means that the nonces can be ordered in arbitrary order.

Note, that this is not enforced by system contracts in any way. Some sanity checks may be present, but the accounts are allowed to do however they like. It is more of a suggestion to the operator on how to manage the mempool.

#### Returned magic value

Now, both accounts and paymasters are required to return a certain magic value upon validation. This magic value will be enforced to be correct on the mainnet, but will be ignored during fee estimation. Unlike Ethereum, the signature verification + fee charging/nonce increment are not included as part of the intrinsic costs of the transaction. These are paid as part of the execution and so they need to be estimated as part of the estimation for the transaction's costs. 

Generally, the accounts are recommended to perform as many operations as during normal validation, but only return the invalid magic in the end of the validation. This will allow to correctly (or at least as correctly as possible) estimate the price for the validation of the account.

## Bootloader

Bootloader is the program that accepts an array of transactions and executes the entire zkSync block. The introduction to why its needed can be found [here](#bootloader). This section will expand on its invariants and methods.

### Playground bootloader vs proved bootloader

For convenience, we use the same implementation of the bootloader both in the mainnet blocks and for emulating ethCalls or other testing activities. *Only* *proved* bootloader is ever used for block-building and thus this document describes only it. 

### Start of the block

It is enforced by the ZKPs, that the state of the bootloader is equivalent to the state of a contract transaction with empty calldata. The only difference is that it starts with all the possible memory pre-allocated (to avoid costs for memory expansion).

For additional efficiency (and our convenience), the bootloader receives its parameters inside its memory. This is the only point of non-determinism: the bootloader *starts with its memory pre-filled with any data the operator wants*. That's why it is responsible for validating the correctness of it and it should never rely on the initial contents of the memory to be correct & valid.

For instance, for each transaction, we check that it is [properly ABI-encoded](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L478) and that the transactions [go exactly one after another](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L471). We also ensure that transactions do not exceed the limits of the memory space allowed for transactions.

### Transaction types & their validation

While the main transaction format is the internal `Transaction` [format](https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/TransactionHelper.sol#L25), it is a struct that is used to represent various kinds of transactions types. It contains a lot of `reserved` fields that could be used depending in the future types of transactions without need for AA to change the interfaces of their contracts.

While most of the fields are self-explanatory, the following two reserved fields are used in all of the current transactions types, except for L1→L2 transactions:

They might be renamed to `nonce` and `value` in the future.

The exact type of the transaction is marked by the `txType` field of the transaction type. There are 5 types currently supported:

- `txType`: 0. It means that this transaction is of legacy transaction type. The following restrictions are enforced:
- `maxFeePerGas=getMaxPriorityFeePerGas` (since it is pre-EIP1559 tx type.
- `reserved1..reserved4` as well as `paymaster` are 0. `paymasterInput` is zero.
- Note, that unlike type 1 and type 2 transactions, `reserved0` field can be set to a non-zero value, denoting that this legacy transaction is EIP-155-compatible and its RLP encoding (as well as signature) should contain the `chainId` of the system.
- `txType`: 1. It means that the transaction is of type 1, i.e. transactions access list. zkSync does not support access lists in any way, so no benefits of fulfilling this list will be provided. The access list is assumed to be empty. The same restrictions as for type 0 are enforced, but also `reserved0` must be 0.
- `txType`: 2. It is EIP1559 transactions. The same restrictions as for type 1 apply, but now `maxFeePerGas` may not be equal to `getMaxPriorityFeePerGas`.
- `txType`: 113. It is zkSync transaction type. This transaction type is intended for AA support. The only restriction that applies to this transaction type: fields `reserved0..reserved4` must be equal to 0.
- `txType`: 255. It is a transaction that comes from L1. There are no restrictions explicitly imposed upon this type of transaction, since the bootloader after executing this transaction [sends the hash of its struct to L1](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L911). The L1 contract ensures that the hash did indeed match the [hash of the encoded struct](https://github.com/matter-labs/era-contracts/blob/main/ethereum/contracts/zksync/facets/Mailbox.sol#L340) on L1.

However, as already stated, the bootloader's memory is not deterministic and the operator is free to put anything it wants there. For all of the transaction types above the restrictions are imposed in the following [method](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L2370), which is called before even starting processing the [transaction](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L489).

### Structure of the bootloader's memory

The bootloader expects the following structure of the memory (here by word we denote 32-bytes, the same machine word as on EVM):

#### **Block information**

- 0 word — the address of the operator (the beneficiary of the transactions).
- 1 word — the hash of the previous block (needed for the support of the `blockhash` opcode). Its validation will be explained later on.
- 2 word — the timestamp of the current block (needed for the support of the `block.timestamp` opcode). Its validation will be explained later on.
- 3 word — the number of the new block (needed for the support of `block.number` opcode).
- 4 word — the L1 gas price provided by the operator.
- 5 word — the "fair" price for L2 gas, i.e. the price below which the `baseFee` of the block should not fall. For now, it is provided by the operator, but it in the future it may become hardcoded.
- 6 word — the base fee for the block that is expected by the operator. While the base fee is deterministic, it is still provided to the bootloader just to make sure that the data that the operator has coincides with the data provided by the bootloader.
- 7 word — reserved word. Unused on proved block.

The block information slots [are used at the beginning of the block](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L50). Once read, these slots can be used for temporary data. 

#### **Temporary data for debug & transaction processing purposes**

- [8..39] words — 32 reserved slots for debugging purposes.
- [40..72] words — 33 slots for holding the paymaster context data for the current transaction. The role of the paymaster context is similar to the [EIP4337](https://eips.ethereum.org/EIPS/eip-4337)'s one. You can read more about it in the account abstraction documentation.
- [73..74] words — 2 slots for signed and explorer transaction hash of the currently processed L2 transaction.
- [75..110] words — 36 slots for the calldata for the KnownCodesContract call.
- [111..366] words — 256 slots for the refunds for the transactions.
- [367..622] words — 256 slots for the overhead for block for the transactions. This overhead is suggested by the operator, i.e. the bootloader will still double-check that the operator does not overcharge the user.

### **Transaction's meta descriptions**

- [623..1135] words — 512 slots for 256 transaction's meta descriptions (their structure is explained below).

For internal reasons related to possible future integrations of zero-knowledge proofs about some of the contents of the bootloader's memory, the array of the transactions is not passed as the ABI-encoding of the array of transactions, but:

- We have a constant maximum number of transactions. At the time of this writing, this number is 256.
- Then, we have 256 transaction descriptions, each ABI encoded as the following struct:

```solidity
struct BootloaderTxDescription {
   // The offset by which the ABI-encoded transaction's data is stored
   uint256 txDataOffset;
   // Auxilary data on the transaction's execution. In our internal versions
   // of the bootloader it may have some special meaning, but for the 
   // bootloader used on the mainnet it has only one meaning: whether to execute
   // the transaction. If 0, no more transactions should be executed. If 1, then 
   // we should execute this transaction and possibly try to execute the next one.
	 uint256 txExecutionMeta;
}
```

#### **Reserved slots for the calldata for the paymaster's postOp operation**

- [1136..1175] words — 40 slots which could be used for encoding the calls for postOp methods of the paymaster.

To avoid additional copying of transactions for calls for the account abstraction, we reserve some of the slots which could be then used to form the calldata for the `postOp` call for the account abstraction without having to copy the entire transaction's data.

#### **The actual transaction's descriptions**

[1175..2^24-258]

Starting from the 653 word, the actual descriptions of the transactions start. (The struct can be found by this [link](https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/TransactionHelper.sol#L25)). The bootloader enforces that:

- They are correctly ABI encoded representations of the struct above.
- They are located without any gaps in memory (the first transaction starts at word 653 and each transaction goes right after the next one).
- The contents of the currently processed transaction (and the ones that will be processed later on are untouched). Note, that we do allow overriding data from the already processed transactions as it helps to preserve efficiency by not having to copy the contents of the `Transaction` each time we need to encode a call to the account.

#### **VM hook pointers**

[2^24-257..2^24 - 255]

These are memory slots that are used purely for debugging purposes (when the VM writes to these slots, the server side can catch these calls and give important insight information for debugging issues).

#### **Result ptr pointer**

[2^24 - 254..2^24]

These are memory slots that are used to track the success status of a transaction. If the transaction with number `i` succeeded, the slot `2^24 - 254 + i` will be marked as 1 and 0 otherwise.

### General flow of the bootloader's execution

1. At the start of the block it reads the initial [block information](#block-information) and sends the information about the current block to the SystemContext system contract.
2. It goes through each of [transaction's descriptions](#the-actual-transactions-descriptions) and checks whether the `execute` field is set. If not, it ends processing of the transactions and ends execution of the block. If the execute field is non-zero, the transaction will be executed and it goes to step 3.
3. Based on the transaction's type it decides whether the transaction is an L1 or L2 transaction and processes them accordingly. More on the processing of the L1 transactions can be read [here](#l1-transactions). More on L2 transactions can be read [here](#l2-transactions).

### L2 transactions

On zkSync, every address is a contract. Users can start transactions from their EOA accounts, because every address that does not have any contract deployed on it implicitly contains the code defined in the DefaultAccount.sol file. Whenever anyone calls a contract that is not in kernel space (i.e. the address is ≥ 2^16) and does not have any contract code deployed on it, the code for DefaultAccount will be used as the contract's code. 

Note, that if you call an account that is in kernel space and does not have any code deployed there, right now, the transaction will revert. This will likely be changed in the future.

We process the L2 transactions according to our account abstraction protocol: [https://v2-docs.zksync.io/dev/tutorials/custom-aa-tutorial.html#prerequisite](https://v2-docs.zksync.io/dev/tutorials/custom-aa-tutorial.html#prerequisite). 

1. We deduct the transaction's upfront payment for the overhead for the block's processing: [https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1013](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1013). You can read more on how that works in the fee model [description](https://www.notion.so/zkSync-fee-model-8e6c9196f4f84105a958a0e2463c3b39).
2. Then we [calculate the gasPrice](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1018) for these transactions according to the EIP1559 rules.
3. We conduct the validation step of the AA protocol: [https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1018](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1018):
 - We [calculate](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1108) the hash of the transaction.
 - If enough gas has been provided, we [near_call](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1124) the validation function in the bootloader. It sets the tx.origin to the address of the bootloader, sets the gasPrice. It also marks the factory dependencies provided by the transaction as marked and then invokes the validation method of the account and verifies the returned magic.
 - Calls the accounts and, if needed, the paymaster to receive the payment for the transaction. Note, that accounts may not use `block.baseFee` context variable, so they have no way to know what exact sum to pay. That's why the accounts typically firstly send `tx.maxFeePerGas * tx.gasLimit` and the bootloader [refunds](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L711) for any excess funds sent. 
4. [We perform the execution of the transaction](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1026). Note, that if the sender is an EOA, tx.origin is set equal to the `from` the value of the transaction. 
5. We [refund](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1034) the user for any excess funds he spent on the transaction:
- Firstly, the postTransaction operation is [called](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1248) to the paymaster.
- The bootloader [asks](https://github.com/code-423n4/2023-03-zksync/blob/main/bootloader/bootloader.yul#L1268) the operator to provide a refund. During the first VM run without proofs the provide directly inserts the refunds in the memory of the bootloader. During the run for the proved blocks, the operator already knows what which values have to be inserted there. You can read more about it in the [documentation](https://www.notion.so/zkSync-fee-model-8e6c9196f4f84105a958a0e2463c3b39) of the fee model.
- The bootloader [refunds](https://github.com/code-423n4/2023-03-zksync/blob/vb-contracts/bootloader/bootloader.yul#L1285) the user.
6. We notify the operator about the [refund](https://github.com/code-423n4/2023-03-zksync/blob/vb-contracts/bootloader/bootloader.yul#L1042) that was granted to the user. It will be used for the correct displaying of gasUsed for the transaction in explorer.

### L1 transactions

We assume that `from` has already authorized the L1→L2 transactions. It also has its L1 pubdata price as well as gasPrice set on L1.

Most of the steps from the execution of L2 transactions are omitted and we set `tx.origin` to the `from`, and `gasPrice` to the one provided by transaction. After that, we use mimicCall to provide the operation itself from the name of the sender account.

[For transactions coming from L1](https://github.com/code-423n4/2023-03-zksync/blob/vb-contracts/bootloader/bootloader.yul#L822), we hash them as well as the result of the transaction (i.e. 1 if successful, 0 otherwise) and [send](https://github.com/code-423n4/2023-03-zksync/blob/vb-contracts/bootloader/bootloader.yul#L911) via L2→L1 messaging mechanism. The L1 contracts are responsible for tracking the consistency and order of the executed L1→L2 transactions.

Note, that for L1→L2 transactions, `reserved0` field denotes the amount of ETH that should be minted on L2 as a result of this transaction. `reserved1` is the refund receiver address, i.e. the address that would receive the refund for the transaction as well as the msg.value if the transaction fails. 

### End of the block

At the end of the block we set `tx.origin` and `tx.gasprice` context variables to zero to save L1 gas on calldata and send the entire bootloader balance to the operator, effectively sending fees to him.

## System contracts

Most of the details on the implementation and the requirements for the execution of system contracts can be found in the doc-comments of their respective code bases. This chapter serves only as a high-level overview of such contracts. 

All the codes of system contracts (including DefaultAccount) are part of the protocol and can only be change via a system upgrade through L1. 

### SystemContext

This contract is used to support various system parameters not included in the VM by default, i.e. `chainId`, `origin`, `gasPrice`, `blockGasLimit`, `coinbase`, `difficulty`, `baseFee`, `blockhash`, `block.number`, `block.timestamp.`

Most of the details of its implementation are rather straightforward and can be seen within its doc-comments. A few things to note:

- The constructor is **not** run for system contracts upon genesis, i.e. the constant context values are set on genesis explicitly. Notably, if in the future we want to upgrade the contracts, we will do it via [ContractDeployer](#contractdeployer-immutablesimulator) and so the constructor will be run.
- When `setNewBlock` is called by the bootloader to set the metadata about the new block as well as the blockhash of the previous ones, this contract sends an L2→L1 log, with the timestamp of the new block as well as the hash of the previous one. The L1 contract is responsible to validate this information.

### AccountCodeStorage

The code hashes of accounts are stored inside the storage of this contract. Whenever a VM calls a contract with address `address` it retrieves the value under storage slot `address` of this system contract, if this value is non-zero, it uses this as the code hash of the account.

Whenever a contract is called, the VM asks the operator to provide the preimage for the codehash of the account. That is why data availability of the code hashes is paramount. You can read more on data availability for the code hashes [here](#knowncodestorage). 

#### Constructing vs Non-constructing code hash

In order to prevent contracts from being able to call a contract during its construction, we set the marker (i.e. second byte of the bytecode hash of the account) as `1`. This way, the VM will ensure that whenever a contract is called without the `is_constructor` flag, the bytecode of the default account (i.e. EOA) will be substituted instead of the original bytecode. 

### BootloaderUtilities

This contract contains some of the methods which are needed purely for the bootloader functionality but were moved out from the bootloader itself for the convenience of not writing this logic in Yul.

### DefaultAccount

Whenever a contract that does **not** both:

- belong to kernel space
- have any code deployed on it (the value stored under the corresponding storage slot in `AccountCodeStorage` is zero)

The code of the default account is used. The main purpose of this contract is to provide EOA-like experience for both wallet users and contracts that call it, i.e. it should not be distinguishable (apart of spent gas) from EOA accounts on Ethereum.

### Ecrecover

Implementation of the ecrecover precompile.

### Empty contracts

Some of the contracts are relied upon to have EOA-like behaviour, i.e. they can be always called and get the success value in return. An example of such address is 0 address. We also require the bootloader to be callable so that the users could transfer ETH to it.

For these contracts, we insert the `EmptyContract` code upon genesis. It is basically a noop code, which does nothing and returns `success=1`.

### Keccak256

Note that unlike Ethereum, keccak256 is a precompile (*not an opcode*) on zkSync. This is the implementation of the keccak256 precompile on zkSync.

### L2EthToken & MsgValueSimulator

Unlike Ethereum, zkEVM does not have any notion of any special native token. That's why we have to simulate operations with Ether via two contracts: `L2EthToken` & `MsgValueSimulator`. 

`L2EthToken` is a contract that holds the balances of ETH for the users. This contract does NOT provide ERC20 interface. The only method for transferring Ether is `transferFromTo`. It permits only some system contracts to transfer on behalf of users. This is needed to ensure that the interface is as close to Ethereum as possible, i.e. the only way to transfer ETH is by doing a call to a contract with some `msg.value`. This is what `MsgValueSimulator` system contract is for.

Whenever anyone wants to do a non-zero value call, they need to call `MsgValueSimulator` with:

- The calldata for the call equal to the original one.
- Pass `value` and whether the call should be marked with `isSystem` in the first extra abi params.
- Pass the address of the callee in the second extraAbiParam.

### KnownCodeStorage

This contract is used to store whether a certain code hash is "known", i.e. can be used to deploy contracts. On zkSync, the L2 stores the contract's code *hashes* and not the codes themselves. Therefore, it must be part of the protocol to ensure that no contract with unknown bytecode (i.e. hash with an unknown preimage) is ever deployed.

The factory dependencies field provided by the user for each transaction contains the list of the contract's bytecode hashes to be marked as known. We can not simply trust the operator to "know" these bytecodehashes as the operator might be malicious and hide the preimage. We ensure the availability of the bytecode in the following way:

- If the transaction comes from L1, i.e. all its factory dependencies have already been published on L1, we can simply mark these dependencies as "known".
- If the transaction comes from L2, i.e. (the factory dependencies are yet to publish on L1), we make the user pays by burning gas proportional to the bytecode's length. After that, we send the L2→L1 log with the bytecode hash of the contract. It is the responsibility of the L1 contracts to verify that the corresponding bytecode hash has been published on L1.

It is the responsibility of the [ContractDeployer](#contractdeployer-immutablesimulator) system contract to deploy only those code hashes that are known.

The KnownCodesStorage contract is also responsible for ensuring that all the "known" bytecode hashes are also [valid](#bytecode-validity).

### ContractDeployer & ImmutableSimulator

`ContractDeployer` is a system contract responsible for deploying contracts on zkSync. It is better to understand how it works in the context of how the contract deployment works on zkSync. Unlike Ethereum, where `create`/`create2` are opcodes, on zkSync these are implemented by the compiler via calls to the ContractDeployer system contract.

For additional security, we also distinguish the deployment of normal contracts and accounts. That's why the main methods that will be used by the user are `create`, `create2`, `createAccount`, `create2Account`, which simulate the CREATE-like and CREATE2-like behavior for deploying normal and account contracts respectively. 

#### **Address derivation**

Each rollup that supports L1→L2 communications needs to make sure that the addresses of contracts on L1 and L2 do not overlap during such communication (otherwise it would be possible that some evil proxy on L1 could mutate the state of the L2 contract). Generally, rollups solve this issue in two ways:

- XOR/ADD some kind of constant to addresses during L1→L2 communication. That's how rollups closer to full EVM-equivalence solve it, since it allows them to maintain the same derivation rules on L1 at the expense of contract accounts on L1 having to redeploy on L2.
- Have different derivation rules from Ethereum. That is the path that zkSync has chosen, mainly because since we have different bytecode than on EVM, CREATE2 address derivation would be different in practice anyway.

You can see the rules for our address derivation in `getNewAddressCreate2`/ `getNewAddressCreate` methods in the ContractDeployer

#### **Deployment nonce**

On Ethereum, the same Nonce is used for CREATE for accounts and EOA wallets. On zkSync this is not the case, we use a separate nonce called "deploymentNonce" to track the nonces for accounts. This was done mostly for consistency with custom accounts and for having multicalls feature in the future.

#### **General process of deployment**

- After incrementing the deployment nonce, the contract deployer must ensure that the bytecode that is being deployed is available.
- After that, it puts the bytecode hash with a special constructing marker as code for the address of the to-be-deployed contract.
- Then, if there is any value passed with the call, the contract deployer passes it to the deployed account and sets the `msg.value` for the next as equal to this value.
- Then, it uses `mimic_call` for calling the constructor of the contract out of the name of the account.
- It parses the array of immutables returned by the constructor (we'll talk about immutables in more details later).
- Calls `ImmutableSimulator` to set the immutables that are to be used for the deployed contract.

Note how it is different from the EVM approach: on EVM when the contract is deployed, it executes the initCode and returns the deployedCode. On zkSync, contracts only have the deployed code and can set immutables as storage variables returned by the constructor.

#### **Constructor**

On Ethereum, the constructor is only part of the initCode that gets executed during the deployment of the contract and returns the deployment code of the contract. On zkSync, there is no separation between deployed code and constructor code. The constructor is always a part of the deployment code of the contract. In order to protect it from being called, the compiler-generated contracts invoke constructor only if the `is_constructor` flag provided* (it is only available for the system contracts). You can read more about flags [here](#flags-for-calls).

After execution, the constructor must return an array of:

```solidity
struct ImmutableData {
    uint256 index;
    bytes32 value;
}
```

basically denoting an array of immutables passed to the contract.

#### **Immutables**

Immutables are stored in the `ImmutableSimulator` system contract. The way how `index` of each immutable is defined is part of the compiler specification. This contract treats it simply as mapping from index to value for each particular address.

Whenever a contract needs to access a value of some immutable, they call the `ImmutableSimulator.getImmutable(getCodeAddress(), index)`. Note that on zkSync it is possible to get the current execution address (you can read more about `getCodeAddress()` [here](#generally-accessible)).

#### **Return value of the deployment methods**

If the call succeeded, the address of the deployed contract is returned. If the deploy fails, the error bubbles up.

### DefaultAccount

The implementation of the default account abstraction. This is the code that is used by default for all addresses that are not in kernel space and have no contract deployed on them. This address:

- Contains minimal implementation of our account abstraction protocol. Note that it supports the [built-in paymaster flows](https://v2-docs.zksync.io/dev/developer-guides/aa.html#paymasters).
- When anyone (except bootloader) calls it, it behaves in the same way as a call to an EOA, i.e. it always returns `success = 1, returndatasize = 0` for calls from anyone except for the bootloader.

### L1Messenger

A contract used for sending arbitrary length L2→L1 messages from zkSync to L1. While zkSync natively supports a rather limited number of L1→L2 logs, which can transfer only roughly 64 bytes of data a time, we allowed sending nearly-arbitrary length L2→L1 messages with the following trick:

The L1 messenger receives a message, hashes it and sends only its hash as well as the original sender via L2→L1 log. Then, it is the duty of the L1 smart contracts to make sure that the operator has provided full preimage of this hash in the commitment of the block.

### NonceHolder

Serves as storage for nonces for our accounts. Besides making it easier for operator to order transactions (i.e. by reading the current nonces of account), it also serves a separate purpose: making sure that the pair (address, nonce) is always unique.

It provides a function `validateNonceUsage` which the bootloader uses to check whether the nonce has been used for a certain account or not. Bootloader enforces that the nonce is marked as non-used before validation step of the transaction and marked as used one afterwards. The contract ensures that once marked as used, the nonce can not be set back to the "unused" state. 

Note that nonces do not necessarily have to be monotonic (this is needed to support a more interesting applications of account abstractions, e.g. protocols that can start transactions on their own, tornado-cash like protocols, etc). That's why there are two ways to set a certain nonce as "used":

- By incrementing the `minNonce` for the account (thus making all nonces that are lower than `minNonce` as used).
- By setting some non-zero value under the nonce via `setValueUnderNonce`. This way, this key will be marked as used and will no longer be allowed to be used as nonce for accounts. This way it is also rather efficient, since these 32 bytes could be used to store some valuable information.

The accounts upon creation can also provide which type of nonce ordering do they want: Sequential (i.e. it should be expected that the nonces grow one by one, just like EOA) or Arbitrary, the nonces may have any values. This ordering is not enforced in any way by system contracts, but it is more of a suggestion to the operator on how it should order the transactions in the mempool.

### SHA256

The implementation of the sha256 precompile

### EventWriter

A system contract responsible for emitting events. 

It accepts in its 0-th extra abi data param the number of topics. In the rest of the extraAbiParams he accepts topics for the event to emit. Note, that in reality the event the first topic of the event contains the address of the account. Generally, the users should not interact with this contract directly, but only through Solidity syntax of `emit`-ing new events.

## Known issues to be resolved

The protocol, while conceptually complete, contains some known issues which will be resolved very soon. 

- Fee modeling is generally not ready, i.e. the final pricing of the opcodes, refunds for transactions (i.e. refunding users for any gas unused during the execution).
- Most certainly we'll add some kind of default implementation for the contracts in the kernel space (i.e. if called, they wouldn't revert but behave like an EOA).

# Scope

*List all files in scope in the table below (along with hyperlinks) -- and feel free to add notes here to emphasize areas of focus.*

*For line of code counts, we recommend using [cloc](https://github.com/AlDanial/cloc).* 

| Contract | SLOC | Purpose | Libraries used |
| ----------- | ----------- | ----------- | ----------- |
| [contracts/folder/sample.sol](contracts/folder/sample.sol) | 123 | This contract does XYZ | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |

## Out of scope

*List any files/contracts that are out of scope for this audit.*


## Scoping Details 
```
- If you have a public code repo, please share it here:  
- How many contracts are in scope?:   44
- Total SLoC for these contracts?:  2700
- How many external imports are there?: 0 
- How many separate interfaces and struct definitions are there for the contracts within scope?:  
- Does most of your code generally use composition or inheritance?:   Inheritance
- How many external calls?:   0
- What is the overall line coverage percentage provided by your tests?:  111111
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?:  true 
- Please describe required context:   Bootloader - a piece of software that takes care of the execution environment initialization
- Does it use an oracle?:  No
- Does the token conform to the ERC20 standard?:  
- Are there any novel or unique curve logic or mathematical models?: Nothing in this code
- Does it use a timelock function?:  
- Is it an NFT?: 
- Does it have an AMM?:   
- Is it a fork of a popular project?:   false
- Does it use rollups?:   Yes
- Is it multi-chain?:  
- Does it use a side-chain?: false
- Describe any specific areas you would like addressed. E.g. Please try to break XYZ.: The focus is on the system contracts, but the bootloader will also be shared and any problems in it are generally in scope
```

# Tests

*Provide every step required to build the project from a fresh git clone, as well as steps to run the tests with a gas report.* 

*Note: Many wardens run Slither as a first pass for testing.  Please document any known errors with no workaround.* 
