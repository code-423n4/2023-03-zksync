# zkSync Era System Contracts contest details
- Total Prize Pool: $180,500 USDC
  - HM awards: $135,000 USDC 
  - QA report awards: $15,000 USDC
  - Gas report awards: $0 USDC 
  - Judge + presort awards: $30,000 USDC 
  - Scout awards: $500 USDC 
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-03-zksync-era-system-contracts-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts March 10, 2023 20:00 UTC
- Ends March 19, 2023 20:00 UTC

**Note for C4 wardens: For this contest, gas optimizations are out of scope. The zkSync team will not be awarding prize funds for gas-specific submissions.**

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](add link to report) within an hour of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

# Overview

## System contracts/bootloader description

### Introduction

#### Bootloader

On standard Ethereum clients, the workflow for executing blocks is the following:

1. Pick a transaction, validate the transactions & charge the fee, execute it.
2. Gather the state changes (if the transaction has not reverted), apply them to the state. 
3. Go back to step (1) if the block gas limit has not been yet exceeded.

However, having such flow on zkSync Era (i.e. processing transaction one-by-one) would be too inefficient, since we have to run the entire proving workflow for each individual transaction. That's what we need the *bootloader* for: instead of running N transactions separately, we run the entire block as a single program that accepts the array of transactions as well as some other block metadata and processes them inside a single big "transaction". The easiest way to think about the bootloader is to think in terms of EntryPoint from EIP4337: it also accepts the array of transactions and facilitates the Account Abstraction protocol.

The hash of the code of the bootloader is stored on L1 and can only be changed as a part of a system upgrade. Note, that unlike system contracts, the bootloader's code is not stored anywhere on L2. That's why we may sometimes refer to the bootloader's address as formal. It only exists for the sake of providing some value to `this`/`msg.sender`/etc. When someone calls the bootloader address (e.g. to pay fees) the [EmptyContract's](#empty-contracts) code is actually invoked.

#### System contracts

While most of the primitive EVM opcodes can be supported out of the box (i.e. zero-value calls, addition/multiplication/memory/storage management, etc), some of the opcodes are not supported by the VM by default and they are implemented via "system contracts" — these contracts are located in a special *kernel space*, i.e. in the address space in range (0..2^16-1), and they have some special privileges, which users' contracts don't have. These contracts are pre-deployed at the genesis and updating their code can be done only via system upgrade, managed from L1.

The use of each system contract will be explained down below.

### zkEVM internals

Full specification of the zkEVM is beyond the scope of this contest. However, this section will give you most of the details needed for understanding the L2 system smart contracts & basic differences between EVM and zkEVM.

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
- A pointer can be converted to the `uint256` integer representing it, but an integer can not be converted to a pointer to prevent unallowed memory access.
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

The same goes with the `calldata`. Whenever a contract starts its execution, it receives the pointer to the calldata. The parent frame can provide any valid pointer as the calldata, which means it can either be a pointer to the slice of the parent's frame memory (heap or auxHeap) or it can be some valid pointer that the parent frame has received before as calldata/returndata.

Contracts simply remember the calldata pointer at the start of the execution frame (it is by the design of the compiler) and remembers the latest received returndata pointer.

Some important implications of this is that it is now possible to do the following calls without any memory copying:

A → B → C

where C receives a slice of the calldata received by B.

The same goes for returning data:

A ← B ← C

There is no need to copy returned data if the B returns a slice of the returndata returned by C.

Note, that you can *not* use the pointer that you received as calldata as returndata (i.e. return it at the end of the execution frame). Otherwise, it would be possible that returndata points to the memory slice of the active frame and allow editing the `returndata`. It means that in the examples above, C could not return a slice of its calldata without memory copying.

These memory optimizations are not expressible in standard Solidity. However, developers may use [compiler simulations](#simulations-via-our-compiler) to manipulate pointers by themselves or use `EfficientCall.sol` library to forward the calldata to the child call.

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

- `mimicCall`. The same as a normal `call`, but it can alter the `msg.sender` field of the transaction.
- `to_l1`. Sends a raw L2→L1 log to Ethereum. The structure of this log can be seen [here](https://github.com/matter-labs/era-contracts/blob/main/ethereum/contracts/zksync/Storage.sol#L44).
- `event`. Emits an L2 log to zkSync. Note, that L2 logs are not equivalent to Ethereum events. Each L2 log can emit 64 bytes of data (the actual size is 88 bytes, because it includes the emitter address, etc). A single Ethereum event is represented with multiple `event` logs. This opcode is only used by `EventWriter` system contract.
- `precompileCall`. This is an opcode that accepts two parameters: the uint256 representing the packed parameters for it as well as the gas to burn. Besides the price for the precompile call itself, it burns the provided gas and executes the precompile. The action that it does depend on `this` during execution:
- If it is the address of the `ecrecover` system contract, it performs the ecrecover operation
- If it is the address of the `sha256`/`keccak256` system contracts, it performs the corresponding hashing operation.
- It does nothing (i.e. just burns gas) otherwise. It can be used to burn gas needed for L2→L1 communication or publication of bytecodes onchain.
- `setValueForNextFarCall` sets `msg.value` for the next `call`/`mimicCall`. Note, that does not mean that the value will be really transferred. It just sets the corresponding `msg.value` context variable. The transferring of ETH should be done via other means by the system contract that uses this parameter.
Note, that this method has no effect on `delegatecall` , since `delegatecall` inherits the `msg.value` of the previous frame.
- `incrementTxCounter` increments the counter of the transactions within the VM. The transaction counter used mostly for the VM's internal tracking of events. Used only in bootloader after the end of each transaction.
- `setPubdataPrice` sets the price (in gas) for publishing a single byte of pubdata.

#### **Generally accessible**

Here are opcodes that can be generally accessed by any contract. Note that while the VM allows to access these methods, it does not mean that this is easy: the compiler might not have convenient support for some use-cases yet. 

- `nearCall`. It is basically a "framed" jump to some location of the code of your contract. The difference between the nearCall and ordinary jump are:
1) It is possible to provide a gas limit for it.
2) If the near call frame panics, all state changes made by it are reversed. Please note, that the memory changes will **not** be reverted.
- `getMeta`. Returns an `uint256` packed value of [ZkSyncMeta](https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/SystemContractHelper.sol#L16) struct. Note that this is not tight packing. The struct is formed by the [following rust code](https://github.com/matter-labs/era-zkevm_opcode_defs/blob/main/src/definitions/abi/meta.rs#L14).
- `getCodeAddress` — receives the address of the executed code. This is different from `this`, since in the case of delegatecalls `this` is preserved, but `codeAddress` is not.

#### Flags for calls

Besides the calldata, it is also possible to provide additional information to the callee when doing `call`, `mimicCall`, `delegateCall`. The called contract will receive the following information in its first 12 registers at the start of execution:

- *r1* — the pointer to the calldata.
- *r2* — the pointer with flags of the call. This is a mask, where each bit is set only if certain flags have been set to the call. Currently, two flags are supported:
0-bit: `isConstructor` flag. This flag can only be set by system contracts and denotes whether the account should execute its constructor logic. Note, unlike Ethereum, there is no separation between the constructor & deployment bytecode.
1-bit: `isSystem` flag. Whether the call intends a system contracts' function. While most of the system contracts' functions are relatively harmless, accessing some with calldata only may break the invariants of Ethereum, e.g. if the system contract uses `mimicCall`: no one expects that by calling a contract some operations may be done out of the name of the caller. This flag can be only set if the callee is in kernel space.
- The rest r3..r12 registers are non-empty only if the `isSystem` flag is set. There may be arbitrary values passed.

The compiler implementation is that these flags are remembered by the contract and can be accessed later during execution via special [simulations](#simulations-via-our-compiler).

If the caller provides inappropriate flags (i.e. tries to set `isSystem` flag when the callee is not in the kernel space), the flags are ignored.

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

A full list of opcode simulations can be found here:

[https://github.com/code-423n4/2023-03-zksync/tree/main/docs/VM-specific_v1.3.0_opcodes_simulation.pdf](https://github.com/code-423n4/2023-03-zksync/tree/main/docs/VM-specific_v1.3.0_opcodes_simulation.pdf)

We also use verbatim-like statements to access zkSync-specific opcodes in the bootloader:

[https://github.com/code-423n4/2023-03-zksync/tree/main/docs/VM-specific_v1.3.0_opcodes_simulation_verbatim.pdf](https://github.com/code-423n4/2023-03-zksync/tree/main/docs/VM-specific_v1.3.0_opcodes_simulation_verbatim.pdf)

All the usages of the simulations in our Solidity code are implemented in these three files:

- [https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/SystemContractHelper.sol](https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/SystemContractHelper.sol)
- [https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/SystemContractsCaller.sol](https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/SystemContractsCaller.sol)
- [https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/EfficientCall.sol](https://github.com/code-423n4/2023-03-zksync/blob/main/contracts/libraries/EfficientCall.sol)

All usages in Yul code are a part of the bootloader implementation.

**Simulating** `nearCall` **(in Yul only)**

In order to use `nearCall` i.e. to call a local function, while providing a limit of gas that this function can use, the following syntax is used:

The function's name should contain `ZKSYNC_NEAR_CALL` string in its name and accept at least 1 input parameter. The first input parameter is the packed ABI of the `nearCall`. Currently, it is equal to the number of gas to be passed with the `nearCall`.

Whenever a `nearCall` panics, the `ZKSYNC_CATCH_NEAR_CALL` function is called.

*Important note:* the compiler behaves in a way that if there is a `revert` in the bootloader, the `ZKSYNC_CATCH_NEAR_CALL` is not called and the parent frame is reverted as well. The only way to revert only the `nearCall` frame is to trigger VM's *panic* (it can be triggered with either an invalid opcode or out of gas error).

*Important note 2:* The 63/64 rule does not apply to `nearCall`.

**Notes on security**

To prevent unintended substitution, the compiler will require `--is-system` flag to be passed during compilation for the above substitutions to work.

### Bytecode hashes

On zkSync the bytecode hashes are stored in the following format:

- The 0th byte denotes the version of the format. Currently, the only version that is used is "1".
- The 1st byte is `0` for deployed contracts' code and `1` for the contract code that is being constructed.
- The 2nd and 3rd bytes denote the length of the contract in 32-byte words as big-endian 2-byte number.
- The next 28 bytes are the last 28 bytes of the sha256 hash of the contract's bytecode.

The bytes are ordered in little-endian order (i.e. the same way as for `bytes32`).

#### Bytecode validity

A bytecode is valid if it:

- Has its length in bytes divisible by 32 (i.e. consists of an integer number of 32-byte words).
- Has a length of fewer than 2^16 words (i.e. its length fits into 2 bytes).
- Has an odd length in words (i.e. the 3rd byte is an odd number).

Note, that it does not have to consist of only correct opcodes. In case the VM encounters an invalid opcode, it will simply revert (similar to how EVM would treat them).

A call to a contract with invalid bytecode can not be proven. That is why it is **essential** that no contract with invalid bytecode is ever deployed on zkSync. It is the job of the [KnownCodesStorage](#knowncodestorage) to ensure that all allowed bytecodes in the system are valid.

## Account abstraction

One of the other important features of zkSync is the support of account abstraction. It is highly recommended to read the documentation on our AA protocol here: [https://era.zksync.io/docs/dev/developer-guides/aa.html#introduction](https://era.zksync.io/docs/dev/developer-guides/aa.html#introduction).

### Features included in the scope

While the description above gives an overview of zkSync Era account abstraction functionality, there are some changes not reflected in the documentation.

#### Refactoring in method naming

The methods have absolutely the same role & functionality, the only difference is naming.

`prePaymaster` → `prepareForPaymaster` 

`postOp` → `postTransaction`

#### Account versioning

Now, each account can also specify which version of the account abstraction protocol they support. This is needed to allow breaking changes in the protocol in the future.

Currently, two versions are supported: `None` (i.e. it is a simple contract and it should never be used as the `from` field of a transaction), and `Version1`.

#### Nonce ordering

Accounts can also signal to the operator which nonce ordering it should expect from these accounts: `Sequential` or `Arbitrary`. 

`Sequential` means that the nonces should be ordered in the same way as in EOAs. This means, that, for instance, the operator will always wait for a transaction with nonce `X` before processing a transaction with nonce `X+1`.

`Arbitrary` means that the nonces can be ordered in arbitrary order.

Note, that this is not enforced by system contracts in any way. Some sanity checks may be present, but the accounts are allowed to do whatever they like. It is more of a suggestion to the operator on how to manage the mempool.

#### Returned magic value

Now, both accounts and paymasters are required to return a certain magic value upon validation. This magic value will be enforced to be correct on the mainnet, but will be ignored during fee estimation. Unlike Ethereum, the signature verification + fee charging/nonce increment is not included as part of the intrinsic costs of the transaction. These are paid as part of the execution and so they need to be estimated as part of the estimation for the transaction's costs. 

Generally, the accounts are recommended to perform as many operations as during normal validation, but only return the invalid magic at the end of the validation. This will allow us to correctly (or at least as correctly as possible) estimate the price for the validation of the account.

## Bootloader

Bootloader is the program that accepts an array of transactions and executes the entire zkSync block. The introduction to why it's needed can be found [here](#bootloader). This section will expand on its invariants and methods.

### Playground bootloader vs proved bootloader

For convenience, we use the same implementation of the bootloader both in the mainnet blocks and for emulating ethCalls or other testing activities. *Only* *proved* bootloader is ever used for block-building and thus this document describes only it. 

### Start of the block

It is enforced by the ZKPs, that the state of the bootloader is equivalent to the state of a contract transaction with empty calldata. The only difference is that it starts with all the possible memory pre-allocated (to avoid costs for memory expansion).

For additional efficiency (and our convenience), the bootloader receives its parameters inside its memory. This is the only point of non-determinism: the bootloader *starts with its memory pre-filled with any data the operator wants*. That's why it is responsible for validating its correctness. It should never rely on the initial contents of the memory to be correct & valid.

For instance, for each transaction, we check that it is [properly ABI-encoded](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L548) and that the transactions [go exactly one after another](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#541). We also ensure that transactions do not exceed the limits of the memory space allowed for transactions.

### Transaction types & their validation

While the main transaction format is the internal `Transaction` [format](https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/TransactionHelper.sol#L25), it is a struct that is used to represent various kinds of transactions types. It contains a lot of `reserved` fields that could be used depending on the future types of transactions without the need for AA to change the interfaces of their contracts.

The exact type of the transaction is marked by the `txType` field of the transaction type. There are 5 types currently supported:

- `txType`: 0. It means that this transaction is of legacy transaction type. The following restrictions are enforced:
  - `maxFeePerGas=getMaxPriorityFeePerGas` (since it is pre-EIP1559 tx type).
  - `reserved1..reserved3` as well as `paymaster` are 0. 
  - `paymasterInput` is empty.

Note, that unlike type 1 and type 2 transactions, `reserved0` field can be set to a non-zero value, denoting that this legacy transaction is EIP-155-compatible and its RLP encoding (as well as signature) should contain the `chainId` of the system.
- `txType`: 1. It means that the transaction is of type 1, i.e. transactions access list. zkSync does not support access lists in any way, so no benefits of fulfilling this list will be provided. The access list is assumed to be empty. The same restrictions as for type 0 are enforced, but also `reserved0` must be 0.
- `txType`: 2. It is EIP1559 transaction. The same restrictions as for type 1 apply, but now `maxFeePerGas` may not be equal to `getMaxPriorityFeePerGas`.
- `txType`: 113. It is zkSync transaction type. This transaction type is intended for AA support. The only restriction that applies to this transaction type: fields `reserved0..reserved3` must be equal to 0.
- `txType`: 255. It is a transaction that comes from L1. There are no restrictions explicitly imposed upon this type of transaction, since the bootloader after executing this transaction [sends the hash of its struct to L1](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L980). The L1 contract ensures that the hash did indeed match the [hash of the encoded struct](https://github.com/matter-labs/era-contracts/blob/main/ethereum/contracts/zksync/facets/Mailbox.sol#L340) on L1.

However, as already stated, the bootloader's memory is not deterministic and the operator is free to put anything it wants there. For all of the transaction types above the restrictions are imposed in the following [method](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L2613), which is called before even starting processing the [transaction](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L559).

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

The block information slots [are used at the beginning of the block](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L50). Once read, these slots can be used for temporary data. 

#### **Temporary data for debug & transaction processing purposes**

- [8..39] words — 32 reserved slots for debugging purposes.
- [40..72] words — 33 slots for holding the paymaster context data for the current transaction. The role of the paymaster context is similar to the [EIP4337](https://eips.ethereum.org/EIPS/eip-4337)’s one. You can read more about it in the account abstraction documentation.
- [73..74] words — 2 slots for signed and explorer transaction hash of the currently processed L2 transaction.
- [75..110] words — 36 slots for the calldata for the KnownCodesContract call.
- [111..1134] words — 1024 slots for the refunds for the transactions.
- [1135..2158] words — 1024 slots for the overhead for the transactions. This overhead is suggested by the operator, i.e. the bootloader will still double-check that the operator does not overcharge the user.
- [2159..3182] words — 1024 slots for the “trusted” gas limits by the operator. The user’s transaction will have at its disposal `min(MAX_TX_GAS(), trustedGasLimit)`, where `MAX_TX_GAS` is a constant guaranteed by the system. Currently, it is equal to 80 million gas. In the future, this feature will be removed.
- [3183..35951] words — 32768 slots used for compressed bytecodes each in the following format: 
- 32 bytecode hash
- 32 zeroes (but then it will be modified to contain 28 zeroes and then the 4-byte selector of the `publishCompressedBytecode` function of the `BytecodeCompresor` 
- The calldata to the bytecode compressor (without the selector).

### **Transaction's meta descriptions**

- [35952..487272] words — 2048 slots for 1024 transaction’s meta descriptions (their structure is explained below).

For internal reasons related to possible future integrations of zero-knowledge proofs about some of the contents of the bootloader's memory, the array of the transactions is not passed as the ABI-encoding of the array of transactions, but:

- We have a constant maximum number of transactions. At the time of this writing, this number is 256.
- Then, we have 256 transaction descriptions, each ABI encoded as the following struct:

```solidity
struct BootloaderTxDescription {
   // The offset by which the ABI-encoded transaction's data is stored
   uint256 txDataOffset;
   // Auxilary data on the transaction's execution. In our internal versions
   // of the bootloader it may have some special meaning, but for the 
   // bootloader used on the mainnet has only one meaning: whether to execute
   // the transaction. If 0, no more transactions should be executed. If 1, then 
   // we should execute this transaction and possibly try to execute the next one.
	 uint256 txExecutionMeta;
}
```

#### **Reserved slots for the calldata for the paymaster's postOp operation**

- [487273..487312] words — 40 slots which could be used for encoding the calls for postOp methods of the paymaster.

To avoid additional copying of transactions for calls for the account abstraction, we reserve some of the slots which could be then used to form the calldata for the `postOp` call for the account abstraction without having to copy the entire transaction's data.

#### **The actual transaction's descriptions**

- [487313..2^24-258]

Starting from the 487313 words, the actual descriptions of the transactions start. (The struct can be found by this [link](https://github.com/code-423n4/2023-03-zksync/tree/main/contracts/libraries/TransactionHelper.sol#L25)). The bootloader enforces that:

- They are correctly ABI encoded representations of the struct above.
- They are located without any gaps in memory (the first transaction starts at word 653 and each transaction goes right after the next one).
- The contents of the currently processed transaction (and the ones that will be processed later on are untouched). Note, that we do allow overriding data from the already processed transactions as it helps to preserve efficiency by not having to copy the contents of the `Transaction` each time we need to encode a call to the account.

#### **VM hook pointers**

- [2^24-1025..2^24 - 1023]

These are memory slots that are used purely for debugging purposes (when the VM writes to these slots, the server side can catch these calls and give important insight information for debugging issues).

#### **Result ptr pointer**

- [2^24 - 1023..2^24]

These are memory slots that are used to track the success status of a transaction. If the transaction with the number `i` succeeded, the slot `2^24 - 1023 + i` will be marked as 1 and 0 otherwise.

### General flow of the bootloader's execution

1. At the start of the block it reads the initial [block information](#block-information) and sends the information about the current block to the SystemContext system contract.
2. It goes through each of [transaction's descriptions](#the-actual-transactions-descriptions) and checks whether the `execute` field is set. If not, it ends both the transaction processing and block execution. If the execute field is non-zero, the transaction will be executed and it goes to step 3.
3. Based on the transaction's type it decides whether the transaction is an L1 or L2 transaction and processes them accordingly. More on the processing of the L1 transactions can be read [here](#l1-transactions). More on L2 transactions can be read [here](#l2-transactions).

### L2 transactions

On zkSync, every address is a contract. Users can start transactions from their EOA accounts because every address that does not have any contract deployed on it implicitly contains the code defined in the DefaultAccount.sol file. Whenever anyone calls a contract that is not in kernel space (i.e. the address is ≥ 2^16) and does not have any contract code deployed on it, the code for DefaultAccount will be used as the contract's code. 

Note, that if you call an account that is in kernel space and does not have any code deployed there, right now, the transaction will revert. This will likely be changed in the future.

We process the L2 transactions according to our account abstraction protocol: [https://era.zksync.io/docs/dev/tutorials/custom-aa-tutorial.html#prerequisite](https://era.zksync.io/docs/dev/tutorials/custom-aa-tutorial.html#prerequisite). 

1. We deduct the transaction's upfront payment for the overhead for the block's processing: [bootloader/bootloader.yul#L1076](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1076). You can read more on how that works in the fee model [description](https://github.com/code-423n4/2023-03-zksync/tree/main/docs/zkSync_fee_model.pdf).
2. Then we [calculate the gasPrice](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1077) for these transactions according to the EIP1559 rules.
3. We conduct the validation step of the AA protocol: [bootloader/bootloader.yul#L1081](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1081):
 - We [calculate](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1176) the hash of the transaction.
 - If enough gas has been provided, we [nearCall](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1192) the validation function in the bootloader. It sets the tx.origin to the address of the bootloader and sets the gasPrice. It also marks the factory dependencies provided by the transaction as marked and then invokes the validation method of the account and verifies the returned magic.
 - Calls the accounts and, if needed, the paymaster to receive the payment for the transaction. Note, that accounts may not use `block.baseFee` context variable, so they have no way to know what exact sum to pay. That's why the accounts typically firstly send `tx.maxFeePerGas * tx.gasLimit` and the bootloader [refunds](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L781) for any excess funds sent. 
4. [We perform the execution of the transaction](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1089). Note, that if the sender is an EOA, tx.origin is set equal to the `from` the value of the transaction. 
5. We [refund](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1092) the user for any excess funds he spent on the transaction:
- Firstly, the postTransaction operation is [called](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1405) to the paymaster.
- The bootloader [asks](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1425) the operator to provide a refund. During the first VM run without proof, the provider directly inserts the refunds in the memory of the bootloader. During the run for the proved blocks, the operator already knows which values have to be inserted there. You can read more about it in the [documentation](https://github.com/code-423n4/2023-03-zksync/tree/main/docs/zkSync_fee_model.pdf) of the fee model.
- The bootloader [refunds](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1442) the user.
6. We notify the operator about the [refund](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L1105) that was granted to the user. It will be used for the correct displaying of gasUsed for the transaction in explorer.

#### Note on fee model

Currently, in order to provide a better UX, the following amendments to the original fee model have been introduced:

- The operator defines the L1 gas price and the corresponding block-wise `gasPerPubdata` is derived from it. The users will be charged exactly `gasPerPubdata` for the pubdata in their transactions regardless of what `gasPerPubdataLimit` they provide. This will allow reducing the overhead for the transaction.
- Since the operator controls L1 gas price, we have decided to temporarily remove the overhead for the pubdata.

#### Trusted gas limit

For L2 transactions, it is possible for the operator to provide the operator's trusted gas limit, which would allow the transaction to have a higher gas limit than the maximum amount of gas mentioned in the fee model. This may happen if the operator accepts the risks of this transaction (e.g. potential DDoS). It is currently used to provide a better UX for publishing bytecodes, where the `gasPerPubdata` may be high enough to allow publishing bytecodes only under a large gas limit.

However, the overhead for the transaction is always calculated as if the transaction did not have a limit higher than `MAX_TX_GAS`. While the operator can increase the available gas beyond `MAX_TX_GAS`, it cannot decrease it below `MAX_TX_GAS`. This means that all L2 transactions are guaranteed to have at least `MAX_TX_GAS` available.

### L1 transactions

We assume that `from` has already authorized the L1→L2 transactions. It also has its L1 pubdata price as well as gasPrice set on L1.

Most of the steps from the execution of L2 transactions are omitted and we set `tx.origin` to the `from`, and `gasPrice` to the one provided by the transaction. After that, we use mimicCall to provide the operation itself from the name of the sender account.

[For transactions coming from L1](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#L980), we hash them as well as the result of the transaction (i.e. 1 if successful, 0 otherwise) and [send](https://github.com/code-423n4/2023-03-zksync/tree/main/bootloader/bootloader.yul#595) via L2→L1 messaging mechanism. The L1 contracts are responsible for tracking the consistency and order of the executed L1→L2 transactions.

Note, that for L1→L2 transactions, `reserved0` field denotes the amount of ETH that should be minted on L2 as a result of this transaction. `reserved1` is the refund receiver address, i.e. the address that would receive the refund for the transaction as well as the msg.value if the transaction fails. 

### End of the block

At the end of the block we set `tx.origin` and `tx.gasprice` context variables to zero to save L1 gas on calldata and send the entire bootloader balance to the operator, effectively sending fees to him.

## Security assumptions of the bootloader

We are building a system ready for decentralization that is resilient to malicious operators. That's why we have a lot of validation checks in there to ensure that the operator can not provide malicious input into the bootloader's memory. However, temporarily the following assumptions are used:

- The operator provides the L1 gas price as a trusted oracle. In the future, a decentralized algorithm will be used to determine the price of L1 gas.
- The operator provides the correct trusted gas limit. While it can not reduce the gas limit lower than `MAX_TX_GAS()`, it is crucial to enable L2 bytecode-heavy operations, e.g. contract deployments. 
- The operator is trusted to provide compressed bytecodes which are advantageous for the users, i.e. it is trusted to make sure that using compression is cheaper than simply publishing the original preimage. 

Any other issues resulting from malicious operator behavior are unexpected and so are welcome to be reported, even though the bootloader is out of scope.

## System contracts

Most of the details on the implementation and the requirements for the execution of system contracts can be found in the doc-comments of their respective code bases. This chapter serves only as a high-level overview of such contracts. 

All the codes of system contracts (including DefaultAccount) are part of the protocol and can only be changed via a system upgrade through L1. 

### SystemContext

This contract is used to support various system parameters not included in the VM by default, i.e. `chainId`, `origin`, `gasPrice`, `blockGasLimit`, `coinbase`, `difficulty`, `baseFee`, `blockhash`, `block.number`, `block.timestamp.`

Most of the details of its implementation are rather straightforward and can be seen within its doc-comments. A few things to note:

- The constructor is **not** run for system contracts upon genesis, i.e. the constant context values are set on genesis explicitly. Notably, if in the future we want to upgrade the contracts, we will do it via [ContractDeployer](#contractdeployer--immutablesimulator) and so the constructor will be run.
- When `setNewBlock` is called by the bootloader to set the metadata about the new block as well as the blockhash of the previous ones, this contract sends an L2→L1 log, with the timestamp of the new block as well as the hash of the previous one. The L1 contract is responsible to validate this information.

### AccountCodeStorage

The code hashes of accounts are stored inside the storage of this contract. Whenever a VM calls a contract with address `address` it retrieves the value under storage slot `address` of this system contract, if this value is non-zero, it uses this as the code hash of the account.

Whenever a contract is called, the VM asks the operator to provide the preimage for the codehash of the account. That is why data availability of the code hashes is paramount. You can read more on data availability for the code hashes [here](#knowncodestorage). 

The contract is also used by the compiler for simulation `extcodehash` and `extcodesize` opcodes.

#### Constructing vs Non-constructing code hash

To prevent contracts from being able to call a contract during its construction, we set the marker (i.e. second byte of the bytecode hash of the account) as `1`. This way, the VM will ensure that whenever a contract is called without the `is_constructor` flag, the bytecode of the default account (i.e. EOA) will be substituted instead of the original bytecode. 

### BootloaderUtilities

This contract contains only one external function that calculates the canonical transaction hash. It is used by the bootloader to determine the hash of the transaction for surreptitious use in AA and infrastructure.

It is separated from the bootloader itself for the convenience of not writing this logic in Yul.

### BytecodeCompressor

This contract is designed to save the L1 gas on publishing the bytecodes on L1. It accepts the original bytecode and its compressed version verifies whether it is possible to restore the original bytecode knowing only the compressed data and the compression algorithm. Then it calls the [KnownCodeStorage](#knowncodestorage) to save the bytecode as known and publish the compressed version on L1.

### DefaultAccount

Whenever a contract that does **not** both:

- belong to kernel space
- have any code deployed on it (the value stored under the corresponding storage slot in `AccountCodeStorage` is zero)

The code of the default account is used. The main purpose of this contract is to provide an EOA-like experience for both wallet users and contracts that call it, i.e. it should not be distinguishable (apart from spent gas) from EOA accounts on Ethereum.

### Ecrecover

The implementation of the ecrecover precompile. It is expected to be used frequently, so written in pure yul with a custom memory layout.

The contract accepts the calldata in the same format as EVM precompile, i.e. the first 32 bytes are the hash, the next 32 bytes are the v, the next 32 bytes are the r, and the last 32 bytes are the s. 

It also validates the input by the same rules as the EVM precompile:
- The v should be either 27 or 28,
- The r and s should be less than the curve order.

After that, it makes a precompile call and returns empty bytes if the call failed, and the recovered address otherwise.

### Empty contracts

Some of the contracts are relied upon to have EOA-like behavior, i.e. they can be always called and get the success value in return. An example of such an address is a 0 address. We also require the bootloader to be callable so that the users could transfer ETH to it.

For these contracts, we insert the `EmptyContract` code upon genesis. It is basically a noop code, which does nothing and returns `success=1`.

### Keccak256 & SHA256

Note that, unlike Ethereum, keccak256 is a precompile (*not an opcode*) on zkSync. 

These system contracts act as wrappers for their respective crypto precompile implementations. They are expected to be used frequently, especially keccak256, since Solidity computes storage slots for mapping and dynamic arrays with its help. That's we wrote contracts on pure yul with optimizing the short input case.

The system contracts accept the input and transform it into the format that the zk-circuit expects. This way, some of the work is shifted from the crypto to smart contracts, which are easier to audit and maintain.

Both contracts should apply padding to the input according to their respective specifications, and then make a precompile call with the padded data. All other hashing work will be done in the zk-circuit. It's important to note that the crypto part of the precompiles expects to work with padded data. This means that a bug in applying padding may lead to an unprovable transaction.

### L2EthToken & MsgValueSimulator

Unlike Ethereum, zkEVM does not have any notion of any special native token. That's why we have to simulate operations with Ether via two contracts: `L2EthToken` & `MsgValueSimulator`. 

`L2EthToken` is a contract that holds the balances of ETH for the users. This contract does NOT provide the ERC20 interface. The only method for transferring Ether is `transferFromTo`. It permits only some system contracts to transfer on behalf of users. This is needed to ensure that the interface is as close to Ethereum as possible, i.e. the only way to transfer ETH is by doing a call to a contract with some `msg.value`. This is what `MsgValueSimulator` system contract is for.

Whenever anyone wants to do a non-zero value call, they need to call `MsgValueSimulator` with:

- The calldata for the call is equal to the original one.
- Pass `value` and whether the call should be marked with `isSystem` in the first extra abi params.
- Pass the address of the callee in the second extraAbiParam.

### KnownCodeStorage

This contract is used to store whether a certain code hash is "known", i.e. can be used to deploy contracts. On zkSync, the L2 stores the contract's code *hashes* and not the codes themselves. Therefore, it must be part of the protocol to ensure that no contract with unknown bytecode (i.e. hash with an unknown preimage) is ever deployed.

The factory dependencies field provided by the user for each transaction contains the list of the contract's bytecode hashes to be marked as known. We can not simply trust the operator to "know" these bytecodehashes as the operator might be malicious and hide the preimage. We ensure the availability of the bytecode in the following way:

- If the transaction comes from L1, i.e. all its factory dependencies have already been published on L1, we can simply mark these dependencies as "known".
- If the transaction comes from L2, i.e. (the factory dependencies are yet to publish on L1), the operator prepares the compress the bytecode offchain and then verifies that the bytecode was compressed correctly. After that, we send the L2→L1 log with the compressed bytecode of the contract. It is the responsibility of the L1 contracts to verify that the corresponding bytecode hash has been published on L1.

It is the responsibility of the [BytecodeCompressor](#bytecodecompressor) system contract to verify that the operator has compressed the bytecode correctly.

It is the responsibility of the [ContractDeployer](#contractdeployer--immutablesimulator) system contract to deploy only those code hashes that are known.

The KnownCodesStorage contract is also responsible for ensuring that all the "known" bytecode hashes are also [valid](#bytecode-validity).

### ContractDeployer & ImmutableSimulator

`ContractDeployer` is a system contract responsible for deploying contracts on zkSync. It is better to understand how it works in the context of how the contract deployment works on zkSync. Unlike Ethereum, where `create`/`create2` are opcodes, on zkSync these are implemented by the compiler via calls to the ContractDeployer system contract.

For additional security, we also distinguish the deployment of normal contracts and accounts. That's why the main methods that will be used by the user are `create`, `create2`, `createAccount`, `create2Account`, which simulate the CREATE-like and CREATE2-like behavior for deploying normal and account contracts respectively. 

#### **Address derivation**

Each rollup that supports L1→L2 communications needs to make sure that the addresses of contracts on L1 and L2 do not overlap during such communication (otherwise it would be possible that some evil proxy on L1 could mutate the state of the L2 contract). Generally, rollups solve this issue in two ways:

- XOR/ADD some kind of constant to address during L1→L2 communication. That's how rollups closer to full EVM-equivalence solve it since it allows them to maintain the same derivation rules on L1 at the expense of contract accounts on L1 having to redeploy on L2.
- Have different derivation rules from Ethereum. That is the path that zkSync has chosen, mainly because since we have different bytecode than on EVM, CREATE2 address derivation would be different in practice anyway.

You can see the rules for our address derivation in `getNewAddressCreate2`/ `getNewAddressCreate` methods in the ContractDeployer

#### **Deployment nonce**

On Ethereum, the same Nonce is used for CREATE for accounts and EOA wallets. On zkSync this is not the case, we use a separate nonce called "deploymentNonce" to track the nonces for accounts. This was done mostly for consistency with custom accounts and for having a multicalls feature in the future.

#### **General process of deployment**

- After incrementing the deployment nonce, the contract deployer must ensure that the bytecode that is being deployed is available.
- After that, it puts the bytecode hash with a special constructing marker as code for the address of the to-be-deployed contract.
- Then, if there is any value passed with the call, the contract deployer passes it to the deployed account and sets the `msg.value` for the next as equal to this value.
- Then, it uses `mimicCall` for calling the constructor of the contract out of the name of the account.
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

Immutables are stored in the `ImmutableSimulator` system contract. The way how `index` of each immutable as defined is part of the compiler specification. This contract treats it simply as mapping from index to value for each particular address.

Whenever a contract needs to access a value of some immutable, they call the `ImmutableSimulator.getImmutable(getCodeAddress(), index)`. Note that on zkSync it is possible to get the current execution address (you can read more about `getCodeAddress()` [here](#generally-accessible)).

#### **Return value of the deployment methods**

If the call succeeded, the address of the deployed contract is returned. If the deployment fails, the error bubbles up.

### DefaultAccount

The implementation of the default account abstraction. This is the code that is used by default for all addresses that are not in kernel space and have no contract deployed on them. This address:

- Contains the minimal implementation of our account abstraction protocol. Note that it supports the [built-in paymaster flows](https://era.zksync.io/docs/dev/developer-guides/aa.html#paymasters).
- When anyone (except bootloader) calls/delegate calls it, it behaves in the same way as a call to an EOA, i.e. it always returns `success = 1, returndatasize = 0` for calls from anyone except for the bootloader.

### L1Messenger

A contract is used for sending arbitrary length L2→L1 messages from zkSync to L1. While zkSync natively supports a rather limited number of L1→L2 logs, which can transfer only roughly 64 bytes of data at a time, we allowed sending nearly-arbitrary length L2→L1 messages with the following trick:

The L1 messenger receives a message, hashes it, and sends only its hash as well as the original sender via the L2→L1 log. Then, it is the duty of the L1 smart contracts to make sure that the operator has provided a full preimage of this hash in the commitment of the block.

### NonceHolder

Serves as storage for nonces for our accounts. Besides making it easier for the operator to order transactions (i.e. by reading the current nonces of account), it also serves a separate purpose: making sure that the pair (address, nonce) is always unique.

It provides a function `validateNonceUsage` which the bootloader uses to check whether the nonce has been used for a certain account or not. Bootloader enforces that the nonce is marked as non-used before the validation step of the transaction and marked as used afterward. The contract ensures that once marked as used, the nonce can not be set back to the "unused" state. 

Note that nonces do not necessarily have to be monotonic (this is needed to support more interesting applications of account abstractions, e.g. protocols that can start transactions on their own, tornado-cash like protocols, etc). That's why there are two ways to set a certain nonce as "used":

- By incrementing the `minNonce` for the account (thus making all nonces that are lower than `minNonce` as used).
- By setting some non-zero value under the nonce via `setValueUnderNonce`. This way, this key will be marked as used and will no longer be allowed to be used as the nonce for accounts. This way it is also rather efficient since these 32 bytes could be used to store some valuable information.

The accounts upon creation can also provide which type of nonce ordering they want: Sequential (i.e. it should be expected that the nonces grow one by one, just like EOA) or Arbitrary, the nonces may have any values. This ordering is not enforced in any way by system contracts, but it is more of a suggestion to the operator on how it should order the transactions in the mempool.

### EventWriter

A system contract is responsible for emitting events. The contract is called every time when another contract emits an event. Expected to be called frequently, so it is written in pure yul to save users gas.

It accepts in its 0-th extra abi data param the number of topics. In the rest of the extraAbiParams he accepts topics for the event to emit. Note, that in reality, the event the first topic of the event contains the address of the account. Generally, the users should not interact with this contract directly, but only through Solidity syntax of `emit`-ing new events.

# Scope

| Contract | SLOC | Purpose | Libraries used |
| ----------- | ----------- | ----------- | ----------- |
| [contracts/openzeppelin/utils/Address.sol](contracts/openzeppelin/utils/Address.sol) | 160 | | |
| [contracts/openzeppelin/token/ERC20/IERC20.sol](contracts/openzeppelin/token/ERC20/IERC20.sol) | 15 | | |
| [contracts/openzeppelin/token/ERC20/utils/SafeERC20.sol](contracts/openzeppelin/token/ERC20/utils/SafeERC20.sol) | 109 | | |
| [contracts/openzeppelin/token/ERC20/extensions/IERC20Permit.sol](contracts/openzeppelin/token/ERC20/extensions/IERC20Permit.sol) | 14 | | |
| [contracts/ImmutableSimulator.sol](contracts/ImmutableSimulator.sol) | 20 | | |
| [contracts/MsgValueSimulator.sol](contracts/MsgValueSimulator.sol) | 33 | | |
| [contracts/interfaces/IImmutableSimulator.sol](contracts/interfaces/IImmutableSimulator.sol) | 9 | | |
| [contracts/interfaces/IContractDeployer.sol](contracts/interfaces/IContractDeployer.sol) | 62 | | |
| [contracts/interfaces/IAccount.sol](contracts/interfaces/IAccount.sol) | 26 | | |
| [contracts/interfaces/IKnownCodesStorage.sol](contracts/interfaces/IKnownCodesStorage.sol) | 7 | | |
| [contracts/interfaces/IBootloaderUtilities.sol](contracts/interfaces/IBootloaderUtilities.sol) | 7 | | |
| [contracts/interfaces/IL1Messenger.sol](contracts/interfaces/IL1Messenger.sol) | 5 | | |
| [contracts/interfaces/ISystemContext.sol](contracts/interfaces/ISystemContext.sol) | 15 | | |
| [contracts/interfaces/IPaymaster.sol](contracts/interfaces/IPaymaster.sol) | 22 | | |
| [contracts/interfaces/IAccountCodeStorage.sol](contracts/interfaces/IAccountCodeStorage.sol) | 8 | | |
| [contracts/interfaces/IMailbox.sol](contracts/interfaces/IMailbox.sol) | 10 | | |
| [contracts/interfaces/IEthToken.sol](contracts/interfaces/IEthToken.sol) | 14 | | |
| [contracts/interfaces/IPaymasterFlow.sol](contracts/interfaces/IPaymasterFlow.sol) | 5 | | |
| [contracts/interfaces/IBytecodeCompressor.sol](contracts/interfaces/IBytecodeCompressor.sol) | 4 | | |
| [contracts/interfaces/IL2StandardToken.sol](contracts/interfaces/IL2StandardToken.sol) | 9 | | |
| [contracts/interfaces/INonceHolder.sol](contracts/interfaces/INonceHolder.sol) | 14 | | |
| [contracts/BootloaderUtilities.sol](contracts/BootloaderUtilities.sol) | 233 | | |
| [contracts/BytecodeCompressor.sol](contracts/BytecodeCompressor.sol) | 32 | | |
| [contracts/EmptyContract.sol](contracts/EmptyContract.sol) | 5 | | |
| [contracts/L2EthToken.sol](contracts/L2EthToken.sol) | 59 | | |
| [contracts/NonceHolder.sol](contracts/NonceHolder.sol) | 82 | | |
| [contracts/DefaultAccount.sol](contracts/DefaultAccount.sol) | 114 | | |
| [contracts/ContractDeployer.sol](contracts/ContractDeployer.sol) | 199 | | |
| [contracts/Constants.sol](contracts/Constants.sol) | 40 | | |
| [contracts/libraries/SystemContractsCaller.sol](contracts/libraries/SystemContractsCaller.sol) | 149 | | |
| [contracts/libraries/SystemContractHelper.sol](contracts/libraries/SystemContractHelper.sol) | 177 | | |
| [contracts/libraries/Utils.sol](contracts/libraries/Utils.sol) | 46 | | |
| [contracts/libraries/UnsafeBytesCalldata.sol](contracts/libraries/UnsafeBytesCalldata.sol) | 15 | | |
| [contracts/libraries/TransactionHelper.sol](contracts/libraries/TransactionHelper.sol) | 313 | | |
| [contracts/libraries/EfficientCall.sol](contracts/libraries/EfficientCall.sol) | 145 | | |
| [contracts/libraries/RLPEncoder.sol](contracts/libraries/RLPEncoder.sol) | 75 | | |
| [contracts/AccountCodeStorage.sol](contracts/AccountCodeStorage.sol) | 54 | | |
| [contracts/KnownCodesStorage.sol](contracts/KnownCodesStorage.sol) | 63 | | |
| [contracts/SystemContext.sol](contracts/SystemContext.sol) | 62 | | |
| [contracts/L1Messenger.sol](contracts/L1Messenger.sol) | 24 | | |

# Out of Scope

| Contract | SLOC | Purpose | Libraries used |
| ----------- | ----------- | ----------- | ----------- |
| [bootloader/bootloader.yul](bootloader/bootloader.yul) | 3060 | | |
| [contracts/test-contracts/TestSystemContract.sol](contracts/test-contracts/TestSystemContract.sol) | 145 | | |
| [contracts/test-contracts/TestSystemContractHelper.sol](contracts/test-contracts/TestSystemContractHelper.sol) | 76 | | |
| [contracts/tests/TransactionHelperTest.sol](contracts/tests/TransactionHelperTest.sol) | 8 | | |
| [contracts/tests/Counter.sol](contracts/tests/Counter.sol) | 7 | | |

# Build

Ensure you have `solc` 0.8.16 on your system, you can download it here: https://github.com/ethereum/solidity/releases/tag/v0.8.16

```bash
yarn install --ignore-engines
yarn build
```

# Tests

This contest is different from others in that it is not a standard EVM Solidity contract, but a core part of the zkEVM system contracts. The usual unit tests are not really helpful here due to the specific use of the contracts, zkEVM, and the compiler.

Instead, we propose to run the big integration test suite. You will be able to run a huge dataset of tests on the original/modified system contracts and compare the results, or add a new test to check the PoC!

## Setup

```
yarn prepare
```

## Running the tests

```
yarn test
```

Please note, we are not running standard hardhat tests, but use the `era-compiler-tester` tool. 

Other instructions can be found in the test suite [README](https://github.com/matter-labs/era-compiler-tester#compiler-tester-integration-test-framework).
