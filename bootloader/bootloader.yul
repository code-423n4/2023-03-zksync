object "Bootloader" {
    code {
    }
    object "Bootloader_deployed" {
        code {
            /// @notice the address that will be the beneficiary of all the fees
            let OPERATOR_ADDRESS := mload(0)

            let GAS_PRICE_PER_PUBDATA := 0

            // Initializing block params
            {
                /// @notice The hash of the previous block
                let PREV_BLOCK_HASH := mload(32)
                /// @notice The timestamp of the block being processed
                let NEW_BLOCK_TIMESTAMP := mload(64)
                /// @notice The number of the new block being processed.
                /// While this number is deterministic for each block, we
                /// still provide it here to ensure consistency between the state
                /// of the VM and the state of the operator.
                let NEW_BLOCK_NUMBER := mload(96)

                /// @notice The gas price on L1 for ETH. In the future, a trustless value will be enforced.
                /// For now, this value is trusted to be fairly provided by the operator.
                let L1_GAS_PRICE := mload(128)

                /// @notice The minimal gas price that the operator agrees upon. 
                /// In the future, it will have an EIP1559-like lower bound.
                let FAIR_L2_GAS_PRICE := mload(160)

                /// @notice The expected base fee by the operator.
                /// Just like the block number, while calculated on the bootloader side,
                /// the operator still provides it to make sure that its data is in sync. 
                let EXPECTED_BASE_FEE := mload(192)

                validateOperatorProvidedPrices(L1_GAS_PRICE, FAIR_L2_GAS_PRICE)

                <!-- @if BOOTLOADER_TYPE=='proved_block' -->

                // Only for the proved block we enforce that the baseFee proposed 
                // by the operator is equal to the expected one. For the playground block, we allow
                // the operator to provide any baseFee the operator wants.
                let baseFee, GAS_PRICE_PER_PUBDATA := getBaseFee(L1_GAS_PRICE, FAIR_L2_GAS_PRICE)
                if iszero(eq(baseFee, EXPECTED_BASE_FEE)) {
                    debugLog("baseFee", baseFee)
                    debugLog("EXPECTED_BASE_FEE", EXPECTED_BASE_FEE)
                    assertionError("baseFee inconsistent")
                }

                setNewBlock(PREV_BLOCK_HASH, NEW_BLOCK_TIMESTAMP, NEW_BLOCK_NUMBER, EXPECTED_BASE_FEE)

                <!-- @endif -->

                <!-- @if BOOTLOADER_TYPE=='playground_block' -->

                let _, GAS_PRICE_PER_PUBDATA := getBaseFee(L1_GAS_PRICE, FAIR_L2_GAS_PRICE)

                let SHOULD_SET_NEW_BLOCK := mload(224)

                switch SHOULD_SET_NEW_BLOCK 
                case 0 {    
                    unsafeOverrideBlock(NEW_BLOCK_TIMESTAMP, NEW_BLOCK_NUMBER, EXPECTED_BASE_FEE)
                }
                default {
                    setNewBlock(PREV_BLOCK_HASH, NEW_BLOCK_TIMESTAMP, NEW_BLOCK_NUMBER, EXPECTED_BASE_FEE)
                }

                <!-- @endif -->
            }

            // While we definitely can not control the gas price on L1, 
            // we need to check the operator does not provide any absurd numbers there
            function MAX_ALLOWED_GAS_PRICE() -> ret {
                // 10k gwei
                ret := 10000000000000
            }

            /// @dev This method ensures that the prices provided by the operator
            /// are not absurdly high
            function validateOperatorProvidedPrices(l1GasPrice, fairL2GasPrice) {
                if gt(l1GasPrice, MAX_ALLOWED_GAS_PRICE()) {
                    assertionError("L1 gas price too high")
                }

                if gt(fairL2GasPrice, MAX_ALLOWED_GAS_PRICE()) {
                    assertionError("L2 fair gas price too high")
                }
            }

            /// @dev Returns the baseFee for this block based on the
            /// L1 gas price and the fair L2 gas price.
            function getBaseFee(l1GasPrice, fairL2GasPrice) -> baseFee, gasPricePerPubdata {
                // By default, we want to provide the fair L2 gas price.
                // That it means that the operator controls
                // what the value of the baseFee will be. In the future, 
                // a better system, aided by EIP1559 should be added. 

                let pubdataBytePriceETH := safeMul(l1GasPrice, L1_GAS_PER_PUBDATA_BYTE(), "aoa")

                baseFee := max(
                    fairL2GasPrice,
                    ceilDiv(pubdataBytePriceETH, MAX_L2_GAS_PER_PUBDATA())
                )
                gasPricePerPubdata := ceilDiv(pubdataBytePriceETH, baseFee)
            }

            /// @dev It should be always possible to submit a transaction 
            /// that consumes such amount of public data.
            function GUARANTEED_PUBDATA_PER_TX() -> ret {
                ret := {{GUARANTEED_PUBDATA_BYTES}}
            }

            /// @dev The maximal gasPerPubdata, which allows users to still be 
            /// able to send `GUARANTEED_PUBDATA_PER_TX` onchain.
            function MAX_L2_GAS_PER_PUBDATA() -> ret {
                ret := div(MAX_GAS_PER_TRANSACTION(), GUARANTEED_PUBDATA_PER_TX())
            }

            /// @dev The computational overhead for a block.
            /// It includes the combined price for 1 instance of all the circuits 
            /// (since they might be partially filled), the price for running
            /// the common parts of the bootloader as well as general maintainance of the system.
            function BLOCK_OVERHEAD_L2_GAS() -> ret {
                ret := {{BLOCK_OVERHEAD_L2_GAS}}
            }

            /// @dev The overhead for the interaction with L1.
            /// It should cover proof verification as well as other minor 
            /// overheads for committing/executing a transaction in a block.
            function BLOCK_OVERHEAD_L1_GAS() -> ret {
                ret := {{BLOCK_OVERHEAD_L1_GAS}}
            }

            /// @dev The maximal number of gas available to the transaction
            function MAX_GAS_PER_TRANSACTION() -> ret {
                ret := {{MAX_GAS_PER_TRANSACTION}}
            }

            /// @dev The maximum number of pubdata bytes that can be published with one
            /// L1 batch
            function MAX_PUBDATA_PER_BLOCK() -> ret {
                ret := {{MAX_PUBDATA_PER_BLOCK}}
            }

            /// @dev The number of L1 gas needed to be spent for
            /// L1 byte. While a single pubdata byte costs `16` gas, 
            /// we demand at least 17 to cover up for the costs of additional
            /// hashing of it, etc.
            function L1_GAS_PER_PUBDATA_BYTE() -> ret {
                ret := 17
            }

            /// @dev The size of the bootloader memory that is to spent by the transaction's
            /// encodings.
            function BOOTLOADER_MEMORY_FOR_TXS() -> ret {
                ret := {{BOOTLOADER_MEMORY_FOR_TXS}}
            }

            /// @dev Whether the block is allowed to accept transactions with
            /// gasPerPubdataByteLimit = 0. On mainnet, this is forbidden for safety reasons.
            function FORBID_ZERO_GAS_PER_PUBDATA() -> ret {
                ret := {{FORBID_ZERO_GAS_PER_PUBDATA}}
            }
            
            /// @dev The maximum number of transactions per L1 batch.
            function MAX_TRANSACTIONS_IN_BLOCK() -> ret {
                ret := {{MAX_TRANSACTIONS_IN_BLOCK}}
            }

            /// @dev The slot from which the scratch space starts.
            /// Scatch space is used for various temporary values
            function SCRATCH_SPACE_BEGIN_SLOT() -> ret {
                ret := 8
            }

            /// @dev The byte from which the scratch space starts.
            /// Scratch space is used for various temporary values
            function SCRATCH_SPACE_BEGIN_BYTE() -> ret {
                ret := mul(SCRATCH_SPACE_BEGIN_SLOT(), 32)
            }

            /// @dev The first 32 slots are reserved for event emitting for the 
            /// debugging purposes
            function SCRATCH_SPACE_SLOTS() -> ret {
                ret := 32
            }

            /// @dev Slots reserved for saving the paymaster context
            /// @dev The paymasters are allowed to consume at most 
            /// 32 slots (1024 bytes) for their context.
            /// The 33 slots are required since the first one stores the length of the calldata.
            function PAYMASTER_CONTEXT_SLOTS() -> ret {
                ret := 33
            }
        
            /// @dev Bytes reserved for saving the paymaster context
            function PAYMASTER_CONTEXT_BYTES() -> ret {
                ret := mul(PAYMASTER_CONTEXT_SLOTS(), 32)
            }

            /// @dev Slot from which the paymaster context starts
            function PAYMASTER_CONTEXT_BEGIN_SLOT() -> ret {
                ret := add(SCRATCH_SPACE_BEGIN_SLOT(), SCRATCH_SPACE_SLOTS())
            }

            /// @dev The byte from which the paymaster context starts
            function PAYMASTER_CONTEXT_BEGIN_BYTE() -> ret {
                ret := mul(PAYMASTER_CONTEXT_BEGIN_SLOT(), 32)
            }

            /// @dev Each tx must have at least this amount of unused bytes before them to be able to 
            /// encode the postOp operation correctly.
            function MAX_POSTOP_SLOTS() -> ret {
                // Before the actual transaction encoding, the postOp contains 6 slots:
                // 1. Context offset
                // 2. Transaction offset
                // 3. Transaction hash
                // 4. Suggested signed hash
                // 5. Transaction result
                // 6. Maximum refunded gas
                // And one more slot for the padding selector
                ret := add(PAYMASTER_CONTEXT_SLOTS(), 7)
            }

            /// @dev Slots needed to store the canonical and signed hash for the current L2 transaction.
            function CURRENT_L2_TX_HASHES_RESERVED_SLOTS() -> ret {
                ret := 2
            }

            /// @dev Slot from which storing of the current canonical and signed hashes begins
            function CURRENT_L2_TX_HASHES_BEGIN_SLOT() -> ret {
                ret := add(PAYMASTER_CONTEXT_BEGIN_SLOT(), PAYMASTER_CONTEXT_SLOTS())
            }

            /// @dev The byte from which storing of the current canonical and signed hashes begins
            function CURRENT_L2_TX_HASHES_BEGIN_BYTE() -> ret {
                ret := mul(CURRENT_L2_TX_HASHES_BEGIN_SLOT(), 32)
            }

            /// @dev The maximum number of new factory deps that are allowed in a transaction
            function MAX_NEW_FACTORY_DEPS() -> ret {
                ret := 32
            }

            /// @dev Besides the factory deps themselves, we also need another 4 slots for: 
            /// selector, marker of whether the user should pay for the pubdata,
            /// the offset for the encoding of the array as well as the length of the array.
            function NEW_FACTORY_DEPS_RESERVED_SLOTS() -> ret {
                ret := add(MAX_NEW_FACTORY_DEPS(), 4)
            }

            /// @dev The slot starting from which the factory dependencies are stored
            function NEW_FACTORY_DEPS_BEGIN_SLOT() -> ret {
                ret := add(CURRENT_L2_TX_HASHES_BEGIN_SLOT(), CURRENT_L2_TX_HASHES_RESERVED_SLOTS())
            }

            /// @dev The byte starting from which the factory dependencies are stored
            function NEW_FACTORY_DEPS_BEGIN_BYTE() -> ret {
                ret := mul(NEW_FACTORY_DEPS_BEGIN_SLOT(), 32)
            }

            /// @dev The slot starting from which the refunds provided by the operator are stored
            function TX_OPERATOR_REFUND_BEGIN_SLOT() -> ret {
                ret := add(NEW_FACTORY_DEPS_BEGIN_SLOT(), NEW_FACTORY_DEPS_RESERVED_SLOTS())
            }

            /// @dev The byte starting from which the refunds provided by the operator are stored
            function TX_OPERATOR_REFUND_BEGIN_BYTE() -> ret {
                ret := mul(TX_OPERATOR_REFUND_BEGIN_SLOT(), 32)
            }

            /// @dev The number of slots dedicated for the refunds for the transactions.
            /// It is equal to the number of transactions in the block.
            function TX_OPERATOR_REFUNDS_SLOTS() -> ret {
                ret := MAX_TRANSACTIONS_IN_BLOCK()
            }

            /// @dev The slot starting from which the overheads proposed by the operator will be stored
            function TX_SUGGESTED_OVERHEAD_BEGIN_SLOT() -> ret {
                ret := add(TX_OPERATOR_REFUND_BEGIN_SLOT(), TX_OPERATOR_REFUNDS_SLOTS())
            }

            /// @dev The byte starting from which the overheads proposed by the operator will be stored
            function TX_SUGGESTED_OVERHEAD_BEGIN_BYTE() -> ret {
                ret := mul(TX_SUGGESTED_OVERHEAD_BEGIN_SLOT(), 32)
            }

            /// @dev The number of slots dedicated for the overheads for the transactions.
            /// It is equal to the number of transactions in the block.
            function TX_SUGGESTED_OVERHEAD_SLOTS() -> ret {
                ret := MAX_TRANSACTIONS_IN_BLOCK()
            }

            /// @dev The slot from which the bootloader transactions' descriptions begin
            function TX_DESCRIPTION_BEGIN_SLOT() -> ret {
                ret := add(TX_SUGGESTED_OVERHEAD_BEGIN_SLOT(), TX_SUGGESTED_OVERHEAD_SLOTS())
            }

            /// @dev The byte from which the bootloader transactions' descriptions begin
            function TX_DESCRIPTION_BEGIN_BYTE() -> ret {
                ret := mul(TX_DESCRIPTION_BEGIN_SLOT(), 32)
            }

            // Each tx description has the following structure
            // 
            // struct BootloaderTxDescription {
            //     uint256 txMeta;
            //     uint256 txDataOffset;
            // }
            //
            // `txMeta` contains flags to manipulate the transaction execution flow.
            // For playground blocks:
            //      It can have the following information (0 byte is LSB and 31 byte is MSB):
            //      0 byte: `execute`, bool. Denotes whether transaction should be executed by the bootloader.
            //      31 byte: server-side tx execution mode
            // For proved blocks:
            //      It can simply denotes whether to execute the transaction (0 to stop executing the block, 1 to continue) 
            //
            // Each such encoded struct consumes 2 words
            function TX_DESCRIPTION_SIZE() -> ret {
                ret := 64
            }

            /// @dev The byte right after the basic description of bootloader transactions
            function TXS_IN_BLOCK_LAST_PTR() -> ret {
                ret := add(TX_DESCRIPTION_BEGIN_BYTE(), mul(MAX_TRANSACTIONS_IN_BLOCK(), TX_DESCRIPTION_SIZE()))
            }

            /// @dev The memory page consists of 2^19 VM words.
            /// Each execution result is a single boolean, but 
            /// for the sake of simplicity we will spend 32 bytes on each
            /// of those for now. 
            function MAX_MEM_SIZE() -> ret {
                ret := 0x1000000 // 2^24 bytes
            }

            function L1_TX_INTRINSIC_L2_GAS() -> ret {
                ret := {{L1_TX_INTRINSIC_L2_GAS}}
            }

            function L1_TX_INTRINSIC_PUBDATA() -> ret {
                ret := {{L1_TX_INTRINSIC_PUBDATA}}
            }

            function L2_TX_INTRINSIC_GAS() -> ret {
                ret := {{L2_TX_INTRINSIC_GAS}}
            }

            function L2_TX_INTRINSIC_PUBDATA() -> ret {
                ret := {{L2_TX_INTRINSIC_PUBDATA}}
            }

            /// @dev The byte from which the pointers on the result of transactions are stored
            function RESULT_START_PTR() -> ret {
                ret := sub(MAX_MEM_SIZE(), mul(MAX_TRANSACTIONS_IN_BLOCK(), 32))
            }

            /// @dev The pointer writing to which invokes the VM hooks
            function VM_HOOK_PTR() -> ret {
                ret := sub(RESULT_START_PTR(), 32)
            }

            /// @dev The maximum number the VM hooks may accept
            function VM_HOOK_PARAMS() -> ret {
                ret := 2
            }

            /// @dev The offset starting from which the parameters for VM hooks are located
            function VM_HOOK_PARAMS_OFFSET() -> ret {
                ret := sub(VM_HOOK_PTR(), mul(VM_HOOK_PARAMS(), 32))
            }

            function LAST_FREE_SLOT() -> ret {
                // The slot right before the vm hooks is the last slot that
                // can be used for transaction's descriptions
                ret := sub(VM_HOOK_PARAMS_OFFSET(), 32)
            }

            /// @dev The formal address of the bootloader
            function BOOTLOADER_FORMAL_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008001
            }

            function MAX_SYSTEM_CONTRACT_ADDR() -> ret {
                ret := 0x000000000000000000000000000000000000ffff
            }

            function ACCOUNT_CODE_STORAGE_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008002
            }

            function KNOWN_CODES_CONTRACT_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008004
            }

            function CONTRACT_DEPLOYER_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008006
            }

            function MSG_VALUE_SIMULATOR_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008009
            }

            function SYSTEM_CONTEXT_ADDR() -> ret {
                ret := 0x000000000000000000000000000000000000800b
            }

            function NONCE_HOLDER_ADDR() -> ret {
                ret := 0x0000000000000000000000000000000000008003
            }

            function ETH_L2_TOKEN_ADDR() -> ret {
                ret := 0x000000000000000000000000000000000000800a
            }

            function BOOTLOADER_UTILITIES() -> ret {
                ret := 0x000000000000000000000000000000000000800c
            }

            /// @dev Whether the bootloader should enforce that accounts have returned the correct
            /// magic value for signature. This value is enforced to be "true" on the main proved block, but 
            /// we need the ability to ignore invalid signature results during fee estimation,
            /// where the signature for the transaction is usually not known beforehand
            function SHOULD_ENSURE_CORRECT_RETURNED_MAGIC() -> ret {
                ret := {{ENSURE_RETURNED_MAGIC}}
            }

            function L1_TX_TYPE() -> ret {
                ret := 255
            }

            /// @dev The overhead in gas that will be used when checking whether the context has enough gas, i.e. 
            /// when checking for X gas, the context should have at least X+CHECK_ENOUGH_GAS_OVERHEAD() gas.
            function CHECK_ENOUGH_GAS_OVERHEAD() -> ret {
                ret := 1000000
            }

            // Now, we iterate over all transactions, processing each of them
            // one by one.
            // Here, the `resultPtr` is the pointer to the memory slot, where we will write
            // `true` or `false` based on whether the tx execution was successful,

            // The position at which the tx offset of the transaction should be placed
            let currentExpectedTxOffset := add(TXS_IN_BLOCK_LAST_PTR(), mul(MAX_POSTOP_SLOTS(), 32))

            let txPtr := TX_DESCRIPTION_BEGIN_BYTE()

            // Iterating through transaction descriptions
            for { 
                let resultPtr := RESULT_START_PTR()
                let transactionIndex := 0 
            } lt(txPtr, TXS_IN_BLOCK_LAST_PTR()) { 
                txPtr := add(txPtr, TX_DESCRIPTION_SIZE())
                resultPtr := add(resultPtr, 32)
                transactionIndex := add(transactionIndex, 1)
            } {
                let execute := mload(txPtr)

                debugLog("txPtr", txPtr)
                debugLog("execute", execute)
                
                if iszero(execute) {
                    // We expect that all transactions that are executed
                    // are continuous in the array.
                    break
                }                

                let txDataOffset := mload(add(txPtr, 0x20))

                // We strongly enforce the positions of transactions
                if iszero(eq(currentExpectedTxOffset, txDataOffset)) {
                    debugLog("currentExpectedTxOffset", currentExpectedTxOffset)
                    debugLog("txDataOffset", txDataOffset)

                    assertionError("Tx data offset is incorrect")
                }

                currentExpectedTxOffset := validateAbiEncoding(txDataOffset)

                // Checking whether the last slot of the transaction's description
                // does not go out of bounds.
                if gt(sub(currentExpectedTxOffset, 32), LAST_FREE_SLOT()) {
                    debugLog("currentExpectedTxOffset", currentExpectedTxOffset)
                    debugLog("LAST_FREE_SLOT", LAST_FREE_SLOT())

                    assertionError("currentExpectedTxOffset too high")
                }

                validateTypedTxStructure(add(txDataOffset, 0x20))
    
                <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                {
                    debugLog("ethCall", 0)
                    processTx(txDataOffset, resultPtr, transactionIndex, 0, GAS_PRICE_PER_PUBDATA)
                }
                <!-- @endif -->
                <!-- @if BOOTLOADER_TYPE=='playground_block' -->
                {
                    let txMeta := mload(txPtr)
                    let processFlags := getWordByte(txMeta, 31)
                    debugLog("flags", processFlags)


                    // `processFlags` argument denotes which parts of execution should be done:
                    //  Possible values:
                    //     0x00: validate & execute (normal mode)
                    //     0x02: perform ethCall (i.e. use mimicCall to simulate the call)

                    let isETHCall := eq(processFlags, 0x02)
                    debugLog("ethCall", isETHCall)
                    processTx(txDataOffset, resultPtr, transactionIndex, isETHCall, GAS_PRICE_PER_PUBDATA)
                }
                <!-- @endif -->
                // Signal to the vm that the transaction execution is complete
                setHook(VM_HOOK_TX_HAS_ENDED())
                // Increment tx index within the system.
                considerNewTx()
            }
            
            // The bootloader doesn't have to pay anything
            setPricePerPubdataByte(0)

            // Resetting tx.origin and gasPrice to 0, so we don't pay for
            // publishing them on-chain.
            setTxOrigin(0)
            setGasPrice(0)

            // Transfering all the ETH received in the block to the operator
            directETHTransfer(
                selfbalance(),
                OPERATOR_ADDRESS
            )

            /// @dev Ceil division of integers
            function ceilDiv(x, y) -> ret {
                switch or(eq(x, 0), eq(y, 0))
                case 0 {
                    // (x + y - 1) / y can overflow on addition, so we distribute.
                    ret := add(div(sub(x, 1), y), 1)
                }
                default {
                    ret := 0
                }
            }
            
            /// @dev Calculates the length of a given number of bytes rounded up to the nearest multiple of 32.
            function lengthRoundedByWords(len) -> ret {
                let neededWords := div(add(len, 31), 32)
                ret := safeMul(neededWords, 32, "xv")
            }

            /// @dev Function responsible for processing the transaction
            /// @param txDataOffset The offset to the ABI-encoding of the structure
            /// @param resultPtr The pointer at which the result of the transaction's execution should be stored
            /// @param transactionIndex The index of the transaction in the block
            /// @param isETHCall Whether the call is an ethCall. 
            /// @param gasPerPubdata The number of L2 gas to charge users for each byte of pubdata 
            /// On proved block this value should always be zero
            function processTx(
                txDataOffset, 
                resultPtr,
                transactionIndex,
                isETHCall,
                gasPerPubdata
            ) {
                let innerTxDataOffset := add(txDataOffset, 0x20)

                // By default we assume that the transaction has failed.
                mstore(resultPtr, 0)

                let userProvidedPubdataPrice := getGasPerPubdataByteLimit(innerTxDataOffset)
                debugLog("userProvidedPubdataPrice:", userProvidedPubdataPrice)

                debugLog("gasPerPubdata:", gasPerPubdata)

                switch isTxFromL1(innerTxDataOffset) 
                    case 1 {
                        // For L1->L2 transactions we always use the pubdata price provided by the transaction. 
                        // This is needed to ensure DDoS protection. All the excess expenditure 
                        // will be refunded to the user.
                        setPricePerPubdataByte(userProvidedPubdataPrice)

                        processL1Tx(txDataOffset, resultPtr, transactionIndex, userProvidedPubdataPrice)
                    }
                    default {
                        // The user has not agreed to this pubdata price
                        if lt(userProvidedPubdataPrice, gasPerPubdata) {
                            revertWithReason(UNACCEPTABLE_GAS_PRICE_ERR_CODE(), 0)
                        }
                        
                        setPricePerPubdataByte(gasPerPubdata)

                        <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                        processL2Tx(txDataOffset, resultPtr, transactionIndex, gasPerPubdata)
                        <!-- @endif -->

                        <!-- @if BOOTLOADER_TYPE=='playground_block' -->
                        switch isETHCall 
                            case 1 {
                                let gasLimit := getGasLimit(innerTxDataOffset)
                                let nearCallAbi := getNearCallABI(gasLimit)
                                checkEnoughGas(gasLimit)
                                ZKSYNC_NEAR_CALL_ethCall(
                                    nearCallAbi,
                                    txDataOffset,
                                    resultPtr
                                )
                            }
                            default { 
                                processL2Tx(txDataOffset, resultPtr, transactionIndex, gasPerPubdata)
                            }
                        <!-- @endif -->
                    }
            }

            /// @dev Calculates the canonical hash of the L1->L2 transaction that will be
            /// sent to L1 as a message to the L1 contract that a certain operation has been processed.
            function getCanonicalL1TxHash(txDataOffset) -> ret {
                // Putting the correct value at the `txDataOffset` just in case, since 
                // the correctness of this value is not part of the system invariants.
                // Note, that the correct ABI encoding of the Transaction structure starts with 0x20
                mstore(txDataOffset, 0x20)

                let innerTxDataOffset := add(txDataOffset, 0x20)
                let dataLength := safeAdd(32, getDataLength(innerTxDataOffset), "qev")

                debugLog("HASH_OFFSET", innerTxDataOffset)
                debugLog("DATA_LENGTH", dataLength)

                ret := keccak256(txDataOffset, dataLength)
            }

            /// @dev The purpose of this function is to make sure that the operator
            /// gets paid for the transaction. Note, that the beneficiary of the payment is 
            /// bootloader.
            /// The operator will be paid at the end of the block.
            function ensurePayment(txDataOffset, gasPrice) {
                // Skipping the first 0x20 byte in the encoding of the transaction.
                let innerTxDataOffset := add(txDataOffset, 0x20)
                let from := getFrom(innerTxDataOffset)
                let requiredETH := safeMul(getGasLimit(innerTxDataOffset), gasPrice, "lal")

                let bootloaderBalanceETH := balance(BOOTLOADER_FORMAL_ADDR())
                let paymaster := getPaymaster(innerTxDataOffset)

                let payer := 0

                switch paymaster
                case 0 {
                    payer := from

                    // There is no paymaster, the user should pay for the execution.
                    // Calling for the `payForTransaction` method of the account.
                    setHook(VM_HOOK_ACCOUNT_VALIDATION_ENTERED())
                    let res := accountPayForTx(from, txDataOffset)
                    setHook(VM_HOOK_NO_VALIDATION_ENTERED())


                    if iszero(res) {
                        revertWithReason(
                            PAY_FOR_TX_FAILED_ERR_CODE(),
                            1
                        )
                    }
                }   
                default {
                    // There is some paymaster present.
                    payer := paymaster 

                    // Firstly, the `prepareForPaymaster` method of the user's account is called.
                    setHook(VM_HOOK_ACCOUNT_VALIDATION_ENTERED())
                    let userPrePaymasterResult := accountPrePaymaster(from, txDataOffset)
                    setHook(VM_HOOK_NO_VALIDATION_ENTERED())

                    if iszero(userPrePaymasterResult) {
                        revertWithReason(
                            PRE_PAYMASTER_PREPARATION_FAILED_ERR_CODE(),
                            1
                        )
                    }

                    // Then, the paymaster is called. The paymaster should pay us in this method.
                    setHook(VM_HOOK_PAYMASTER_VALIDATION_ENTERED())
                    let paymasterPaymentSuccess := validateAndPayForPaymasterTransaction(paymaster, txDataOffset)
                    if iszero(paymasterPaymentSuccess) {
                        revertWithReason(
                            PAYMASTER_VALIDATION_FAILED_ERR_CODE(),
                            1
                        )
                    }

                    storePaymasterContextAndCheckMagic()
                    setHook(VM_HOOK_NO_VALIDATION_ENTERED())
                }

                let bootloaderReceivedFunds := safeSub(balance(BOOTLOADER_FORMAL_ADDR()), bootloaderBalanceETH, "qsx")

                // If the amount of funds provided to the bootloader is less than the minimum required one
                // then this transaction should be rejected.                
                if lt(bootloaderReceivedFunds, requiredETH)  {
                    revertWithReason(
                        FAILED_TO_CHARGE_FEE_ERR_CODE(),
                        0
                    )
                }

                let excessiveFunds := safeSub(bootloaderReceivedFunds, requiredETH, "llm") 

                if gt(excessiveFunds, 0) {
                    // Returning back the excessive funds taken.
                    directETHTransfer(excessiveFunds, payer)
                }
            }

            /// @notice Mints ether to the recipient
            /// @param to -- the address of the recipient 
            /// @param amount -- the amount of ETH to mint
            /// @param useNearCallPanic -- whether to use nearCallPanic in case of
            /// the transaction failing to execute. It is desirable in cases
            /// where we want to allow the method fail without reverting the entire bootloader
            function mintEther(to, amount, useNearCallPanic) {
                mstore(0, {{RIGHT_PADDED_MINT_ETHER_SELECTOR}})
                mstore(4, to)
                mstore(36, amount)
                let success := call(
                    gas(),
                    ETH_L2_TOKEN_ADDR(),
                    0,
                    0,
                    68,
                    0,
                    0
                )
                if iszero(success) {
                    switch useNearCallPanic 
                    case 0 {
                        revertWithReason(
                            MINT_ETHER_FAILED_ERR_CODE(),
                            0
                        )
                    }
                    default {
                        nearCallPanic()
                    }
                }
            }

            /// @dev Saves the paymaster context and checks that the paymaster has returned the correct 
            /// magic value.
            /// @dev IMPORTANT: this method should be called right after 
            /// the validateAndPayForPaymasterTransaction method to keep the `returndata` from that transaction
            function storePaymasterContextAndCheckMagic()    {
                // The paymaster validation step should return context of type "bytes context"
                // This means that the returndata is encoded the following way:
                // 0x20 || context_len || context_bytes...
                let returnlen := returndatasize()
                // The minimal allowed returndatasize is 64: magicValue || offset
                if lt(returnlen, 0x40) {
                    revertWithReason(
                        PAYMASTER_RETURNED_INVALID_CONTEXT(),
                        0
                    )
                }

                // Note that it is important to copy the magic even though it is not needed if the
                // `SHOULD_ENSURE_CORRECT_RETURNED_MAGIC` is false. It is never false in production
                // but it is so in fee estimation and we want to preserve as many operations as 
                // in the original operation.
                {
                    returndatacopy(0, 0, 0x20)
                    let magic := mload(0)

                    let isMagicCorrect := eq(magic, {{SUCCESSFUL_PAYMASTER_VALIDATION_MAGIC_VALUE}})

                    if and(iszero(isMagicCorrect), SHOULD_ENSURE_CORRECT_RETURNED_MAGIC()) {
                        revertWithReason(
                            PAYMASTER_RETURNED_INVALID_MAGIC_ERR_CODE(),
                            0
                        )
                    }
                }

                returndatacopy(0, 32, 32)
                let returnedContextOffset := mload(0)

                // Can not read the returned length
                if gt(safeAdd(returnedContextOffset, 32, "lhf"), returnlen) {
                    revertWithReason(
                        PAYMASTER_RETURNED_INVALID_CONTEXT(),
                        0
                    )
                }

                // Reading the length of the context
                returndatacopy(0, returnedContextOffset, 32)
                let returnedContextLen := lengthRoundedByWords(mload(0))

                // The returned context's size should not exceed the maximum length
                if gt(returnedContextLen, PAYMASTER_CONTEXT_BYTES()) {
                    revertWithReason(
                        PAYMASTER_RETURNED_CONTEXT_IS_TOO_LONG(),
                        0
                    )
                }

                if gt(add(returnedContextOffset, add(0x20, returnedContextLen)), returnlen) {
                    revertWithReason(
                        PAYMASTER_RETURNED_CONTEXT_IS_TOO_LONG(),
                        0
                    )
                }

                returndatacopy(PAYMASTER_CONTEXT_BEGIN_BYTE(), returnedContextOffset, add(0x20, returnedContextLen))
            }

            /// @dev The function responsible for processing L1->L2 transactions.
            /// @param txDataOffset The offset to the transaction's information
            /// @param resultPtr The pointer at which the result of the execution of this transaction
            /// @param transactionIndex The index of the transaction
            /// @param gasPerPubdata The price per pubdata to be used
            /// should be stored.
            function processL1Tx(
                txDataOffset,
                resultPtr,
                transactionIndex,
                gasPerPubdata
            ) {
                // Skipping the first formal 0x20 byte
                let innerTxDataOffset := add(txDataOffset, 0x20) 

                let gasLimitForTx := getGasLimitForTx(
                    innerTxDataOffset, 
                    transactionIndex, 
                    gasPerPubdata, 
                    L1_TX_INTRINSIC_L2_GAS(), 
                    L1_TX_INTRINSIC_PUBDATA(),
                    0
                )

                let gasUsedOnPreparation := 0
                let canonicalL1TxHash := 0

                canonicalL1TxHash, gasUsedOnPreparation := l1TxPreparation(txDataOffset)

                let refundGas := 0
                let success := 0

                // The invariant that the user deposited more than the value needed
                // for the transaction must be enforced on L1, but we double check it here
                let gasLimit := getGasLimit(innerTxDataOffset)

                // Note, that for now the property of block.base <= tx.maxFeePerGas does not work 
                // for L1->L2 transactions. For now, these transactions are processed with the same gasPrice
                // they were provided on L1. In the future, we may apply a new logic for it.
                let gasPrice := getMaxFeePerGas(innerTxDataOffset)
                let txInternalCost := safeMul(gasPrice, gasLimit, "poa")
                let value := getValue(innerTxDataOffset)
                if lt(getReserved0(innerTxDataOffset), safeAdd(value, txInternalCost, "ol")) {
                    assertionError("deposited eth too low")
                }
                
                if gt(gasLimitForTx, gasUsedOnPreparation) {
                    let potentialRefund := 0

                    potentialRefund, success := getExecuteL1TxAndGetRefund(txDataOffset, sub(gasLimitForTx, gasUsedOnPreparation))

                    // Asking the operator for refund
                    askOperatorForRefund(potentialRefund)

                    // In case the operator provided smaller refund than the one calculated
                    // by the bootloader, we return the refund calculated by the bootloader.
                    refundGas := max(getOperatorRefundForTx(transactionIndex), potentialRefund)
                }

                let payToOperator := safeMul(gasPrice, safeSub(gasLimit, refundGas, "lpah"), "mnk")

                // Note, that for now, the L1->L2 transactions are free, i.e. the gasPrice
                // for such transactions is always zero, so the `refundGas` is not used anywhere
                // except for notifications for the operator for API purposes. 
                notifyAboutRefund(refundGas)

                // Paying the fee to the operator
                mintEther(BOOTLOADER_FORMAL_ADDR(), payToOperator, false)

                let toRefundRecipient
                switch success
                case 0 {
                    // If the transaction reverts, then minting the msg.value to the user has been reverted
                    // as well, so we can simply mint everything that the user has deposited to 
                    // the refund recipient

                    toRefundRecipient := safeSub(getReserved0(innerTxDataOffset), payToOperator, "vji")
                }
                default {
                    // If the transaction succeeds, then it is assumed that msg.value was transferred correctly. However, the remaining 
                    // ETH deposited will be given to the refund recipient.

                    toRefundRecipient := safeSub(getReserved0(innerTxDataOffset), safeAdd(getValue(innerTxDataOffset), payToOperator, "kpa"), "ysl")
                }

                if gt(toRefundRecipient, 0) {
                    mintEther(getReserved1(innerTxDataOffset), toRefundRecipient, false)
                } 

                mstore(resultPtr, success)
                
                debugLog("Send message to L1", success)
                
                // Sending the L2->L1 to notify the L1 contracts that the priority 
                // operation has been processed.
                sendToL1(true, canonicalL1TxHash, success)
            }

            function getExecuteL1TxAndGetRefund(txDataOffset, gasForExecution) -> potentialRefund, success {
                debugLog("gasForExecution", gasForExecution)

                let callAbi := getNearCallABI(gasForExecution)
                debugLog("callAbi", callAbi)

                checkEnoughGas(gasForExecution)

                let gasBeforeExecution := gas()
                success := ZKSYNC_NEAR_CALL_executeL1Tx(
                    callAbi,
                    txDataOffset
                )
                notifyExecutionResult(success)
                let gasSpentOnExecution := sub(gasBeforeExecution, gas())

                potentialRefund := sub(gasForExecution, gasSpentOnExecution)
                if gt(gasSpentOnExecution, gasForExecution) {
                    potentialRefund := 0
                }
            }

            /// @dev The function responsible for doing all the pre-execution operations for L1->L2 transactions.
            /// @param txDataOffset The offset to the transaction's information
            /// @return canonicalL1TxHash The hash of processed L1->L2 transaction
            /// @return gasUsedOnPreparation The number of L2 gas used in the preparation stage
            function l1TxPreparation(txDataOffset) -> canonicalL1TxHash, gasUsedOnPreparation {
                let innerTxDataOffset := add(txDataOffset, 0x20)
                
                let gasBeforePreparation := gas()
                debugLog("gasBeforePreparation", gasBeforePreparation)

                // Even though the smart contracts on L1 should make sure that the L1->L2 provide enough gas to generate the hash
                // we should still be able to do it even if this protection layer fails.
                canonicalL1TxHash := getCanonicalL1TxHash(txDataOffset)
                debugLog("l1 hash", canonicalL1TxHash)

                markFactoryDepsForTx(innerTxDataOffset, true)

                gasUsedOnPreparation := safeSub(gasBeforePreparation, gas(), "xpa")
                debugLog("gasUsedOnPreparation", gasUsedOnPreparation)
            }

            /// @dev Returns the gas price that should be used by the transaction 
            /// based on the EIP1559's maxFeePerGas and maxPriorityFeePerGas.
            /// The following invariants should hold:
            /// maxPriorityFeePerGas <= maxFeePerGas
            /// baseFee <= maxFeePerGas
            /// While we charge baseFee from the users, the method is mostly used as a method for validating 
            /// the correctness of the fee parameters
            function getGasPrice(
                maxFeePerGas,
                maxPriorityFeePerGas
            ) -> ret {
                let baseFee := basefee()

                if gt(maxPriorityFeePerGas, maxFeePerGas) {
                    revertWithReason(
                        MAX_PRIORITY_FEE_PER_GAS_GREATER_THAN_MAX_FEE_PER_GAS(),
                        0
                    )
                }

                if gt(baseFee, maxFeePerGas) {
                    revertWithReason(
                        BASE_FEE_GREATER_THAN_MAX_FEE_PER_GAS(),
                        0
                    )
                }

                // We always use `baseFee` to charge the transaction 
                ret := baseFee
            }

            /// @dev The function responsible for processing L2 transactions.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param resultPtr The pointer at which the result of the execution of this transaction
            /// should be stored.
            /// @param transactionIndex The index of the current transaction.
            /// @param gasPerPubdata The L2 gas to be used for each byte of pubdata published onchain.
            /// @dev This function firstly does the validation step and then the execution step in separate near_calls.
            /// It is important that these steps are split to avoid rollbacking the state made by the validation step.
            function processL2Tx(
                txDataOffset,
                resultPtr,
                transactionIndex,
                gasPerPubdata
            ) {
                let innerTxDataOffset := add(txDataOffset, 32)

                // Firsly, we publish all the bytecodes needed. This is needed to be done separately, since
                // bytecodes usually form the bulk of the L2 gas prices.
                let spentOnFactoryDeps
                {
                    let preFactoryDep := gas()
                    markFactoryDepsForTx(innerTxDataOffset, false)
                    spentOnFactoryDeps := sub(preFactoryDep, gas())
                }
                
                let gasLimitForTx := getGasLimitForTx(innerTxDataOffset, transactionIndex, gasPerPubdata, L2_TX_INTRINSIC_GAS(), L2_TX_INTRINSIC_PUBDATA(), spentOnFactoryDeps)
                let gasPrice := getGasPrice(getMaxFeePerGas(innerTxDataOffset), getMaxPriorityFeePerGas(innerTxDataOffset))

                debugLog("gasLimitForTx", gasLimitForTx)

                let gasLeft := l2TxValidation(
                    txDataOffset,
                    gasLimitForTx,
                    gasPrice
                )

                let gasSpentOnExecute := 0
                let success := 0
                success, gasSpentOnExecute := l2TxExecution(txDataOffset, gasLeft)

                let refund := 0
                let gasToRefund := sub(gasLeft, gasSpentOnExecute)
                if lt(gasLeft, gasSpentOnExecute){
                    gasToRefund := 0
                }

                refund := refundCurrentL2Transaction(
                    txDataOffset,
                    transactionIndex,
                    success,
                    gasToRefund,
                    gasPrice
                )

                notifyAboutRefund(refund)
                mstore(resultPtr, success)
            }

            /// @dev Calculates the L2 gas limit for the transaction's body, i.e. without intrinsic costs and overhead.
            /// @param innerTxDataOffset The offset for the ABI-encoded Transaction struct fields.
            /// @param transactionIndex The index of the transaction within the block.
            /// @param gasPerPubdata The price for a pubdata byte in L2 gas.
            /// @param intrinsicGas The intrinsic number of L2 gas required for transaction processing.
            /// @param intrinsicPubdata The intrinsic number of pubdata bytes required for transaction processing.
            /// @return gasLimitForTx The maximum number of L2 gas that can be spent on a transaction.
            function getGasLimitForTx(
                innerTxDataOffset,
                transactionIndex,
                gasPerPubdata,
                intrinsicGas,
                intrinsicPubdata,
                preSpent
            ) -> gasLimitForTx {
                let totalGasLimit := getGasLimit(innerTxDataOffset)
                let txEncodingLen := safeAdd(0x20, getDataLength(innerTxDataOffset), "lsh")

                let operatorOverheadForTransaction := getVerifiedOperatorOverheadForTx(
                    transactionIndex,
                    totalGasLimit,
                    gasPerPubdata,
                    txEncodingLen
                )
                gasLimitForTx := safeSub(totalGasLimit, operatorOverheadForTransaction, "qr")

                let intrinsicOverhead := safeAdd(
                    intrinsicGas, 
                    // the error messages are trimmed to fit into 32 bytes
                    safeMul(intrinsicPubdata, gasPerPubdata, "qw"),
                    "fj" 
                )
                preSpent := safeAdd(preSpent, intrinsicOverhead, "pl")

                switch lt(gasLimitForTx, preSpent)
                case 1 {
                    gasLimitForTx := 0
                }
                default {
                    gasLimitForTx := sub(gasLimitForTx, preSpent)
                }

                // Making sure that the body of the transaction does not have more gas
                // than allowed by DDoS safety
                gasLimitForTx := min(MAX_GAS_PER_TRANSACTION(), gasLimitForTx)
            }

            /// @dev The function responsible for the L2 transaction validation.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param gasLimitForTx The L2 gas limit for the transaction validation & execution.
            /// @param gasPrice The L2 gas price that should be used by the transaction.
            /// @return ergsLeft The ergs left after the validation step.
            function l2TxValidation(
                txDataOffset,
                gasLimitForTx,
                gasPrice
            ) -> gasLeft {
                let gasBeforeValidate := gas()

                debugLog("gasBeforeValidate", gasBeforeValidate)

                // Saving the tx hash and the suggested signed tx hash to memory
                saveTxHashes(txDataOffset)

                
                checkEnoughGas(gasLimitForTx)

                // Note, that it is assumed that `ZKSYNC_NEAR_CALL_validateTx` will always return true
                // unless some error which made the whole bootloader to revert has happened or
                // it runs out of gas.
                let isValid := 0

                // Only if the gasLimit for tx is non-zero, we will try to actually run the validation
                if gasLimitForTx {
                    let validateABI := getNearCallABI(gasLimitForTx)

                    debugLog("validateABI", validateABI)

                    isValid := ZKSYNC_NEAR_CALL_validateTx(validateABI, txDataOffset, gasPrice)                    
                }

                debugLog("isValid", isValid)

                let gasUsedForValidate := sub(gasBeforeValidate, gas())
                debugLog("gasUsedForValidate", gasUsedForValidate)

                gasLeft := sub(gasLimitForTx, gasUsedForValidate)
                if lt(gasLimitForTx, gasUsedForValidate) {
                    gasLeft := 0
                }

                // isValid can only be zero if the validation has failed with out of gas
                if or(iszero(gasLeft), iszero(isValid)) {
                    revertWithReason(TX_VALIDATION_OUT_OF_GAS(), 0)
                }

                setHook(VM_HOOK_VALIDATION_STEP_ENDED())
            }

            /// @dev The function responsible for the execution step of the L2 transaction.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param ergsLeft The ergs left after the validation step.
            /// @return success Whether or not the execution step was successful.
            /// @return ergsSpentOnExecute The ergs spent on the transaction execution.
            function l2TxExecution(
                txDataOffset,
                gasLeft,
            ) -> success, gasSpentOnExecute {
                let executeABI := getNearCallABI(gasLeft)
                checkEnoughGas(gasLeft)

                let gasBeforeExecute := gas()
                // for this one, we don't care whether or not it fails.
                success := ZKSYNC_NEAR_CALL_executeL2Tx(
                    executeABI,
                    txDataOffset
                )
                notifyExecutionResult(success)
                gasSpentOnExecute := sub(gasBeforeExecute, gas())
            }

            /// @dev Function responsible for the validation & fee payment step of the transaction. 
            /// @param abi The nearCall ABI. It is implicitly used as gasLimit for the call of this function.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param gasPrice The gasPrice to be used in this transaction.
            function ZKSYNC_NEAR_CALL_validateTx(
                abi,
                txDataOffset,
                gasPrice
            ) -> ret {
                // For the validation step we always use the bootloader as the tx.origin of the transaction
                setTxOrigin(BOOTLOADER_FORMAL_ADDR())
                setGasPrice(gasPrice)
                
                // Skipping the first 0x20 word of the ABI-encoding
                let innerTxDataOffset := add(txDataOffset, 0x20)
                debugLog("Starting validation", 0)

                accountValidateTx(txDataOffset)
                debugLog("Tx validation complete", 1)
                
                ensurePayment(txDataOffset, gasPrice)
                
                ret := 1
            }

            /// @dev Function responsible for the execution of the L2 transaction.
            /// It includes both the call to the `executeTransaction` method of the account
            /// and the call to postOp of the account. 
            /// @param abi The nearCall ABI. It is implicitly used as gasLimit for the call of this function.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            function ZKSYNC_NEAR_CALL_executeL2Tx(
                abi,
                txDataOffset
            ) -> success {
                // Skipping the first word of the ABI-encoding encoding
                let innerTxDataOffset := add(txDataOffset, 0x20)
                let from := getFrom(innerTxDataOffset)

                debugLog("Executing L2 tx", 0)
                // The tx.origin can only be an EOA
                switch isEOA(from)
                case true {
                    setTxOrigin(from)
                }  
                default {
                    setTxOrigin(BOOTLOADER_FORMAL_ADDR())
                }

                success := executeL2Tx(txDataOffset, from)
                debugLog("Executing L2 ret", success)
            }

            /// @dev Used to refund the current transaction. 
            /// The gas that this transaction consumes has been already paid in the 
            /// process of the validation
            function refundCurrentL2Transaction(
                txDataOffset,
                transactionIndex,
                success, 
                gasLeft,
                gasPrice
            ) -> finalRefund {
                setTxOrigin(BOOTLOADER_FORMAL_ADDR())

                finalRefund := 0

                let innerTxDataOffset := add(txDataOffset, 0x20)

                let paymaster := getPaymaster(innerTxDataOffset)
                let refundRecipient := 0
                switch paymaster
                case 0 {
                    // No paymaster means that the sender should receive the refund
                    refundRecipient := getFrom(innerTxDataOffset)
                }
                default {
                    refundRecipient := paymaster
                    
                    if gt(gasLeft, 0) {
                        let nearCallAbi := getNearCallABI(gasLeft)
                        let gasBeforePostOp := gas()
                        pop(ZKSYNC_NEAR_CALL_callPostOp(
                            // Maximum number of gas that the postOp could spend
                            nearCallAbi,
                            paymaster,
                            txDataOffset,
                            success,
                            gasLeft
                        ))
                        let gasSpentByPostOp := sub(gasBeforePostOp, gas())

                        switch gt(gasLeft, gasSpentByPostOp) 
                        case 1 { 
                            gasLeft := sub(gasLeft, gasSpentByPostOp)
                        }
                        default {
                            gasLeft := 0
                        }
                    } 
                }

                askOperatorForRefund(gasLeft)

                let operatorProvidedRefund := getOperatorRefundForTx(transactionIndex)

                // If the operator provides the value that is lower than the one suggested for 
                // the bootloader, we will use the one calculated by the bootloader.
                let refundInGas := max(operatorProvidedRefund, gasLeft)
                if iszero(validateUint32(refundInGas)) {
                    assertionError("refundInGas is not uint32")
                }

                let ethToRefund := safeMul(
                    refundInGas, 
                    gasPrice, 
                    "fdf" // The message is shortened to fit into 32 bytes
                ) 

                directETHTransfer(ethToRefund, refundRecipient)

                finalRefund := refundInGas
            }

            /// @notice A function that transfers ETH directly through the L2EthToken system contract.
            /// Note, that unlike classical EVM transfers it does NOT call the recipient, but only changes the balance.
            function directETHTransfer(amount, recipient) {
                let ptr := 0
                mstore(ptr, {{PADDED_TRANSFER_FROM_TO_SELECTOR}})
                mstore(add(ptr, 4), BOOTLOADER_FORMAL_ADDR())
                mstore(add(ptr, 36), recipient)
                mstore(add(ptr, 68), amount)

                let transferSuccess := call(
                    gas(),
                    ETH_L2_TOKEN_ADDR(),
                    0,
                    0, 
                    100,
                    0,
                    0
                )

                if iszero(transferSuccess) {
                    assertionError("Failed to refund")
                }
            }

            /// @dev Return the operator suggested transaction refund.
            function getOperatorRefundForTx(transactionIndex) -> ret {
                let refundPtr := add(TX_OPERATOR_REFUND_BEGIN_BYTE(), mul(transactionIndex, 32))
                ret := mload(refundPtr)
            }

            /// @dev Return the operator suggested transaction overhead cost.
            function getOperatorOverheadForTx(transactionIndex) -> ret {
                let txBlockOverheadPtr := add(TX_SUGGESTED_OVERHEAD_BEGIN_BYTE(), mul(transactionIndex, 32))
                ret := mload(txBlockOverheadPtr)
            }

            /// @dev Get checked for overcharged operator's overhead for the transaction.
            /// @param transactionIndex The index of the transaction in the batch
            /// @param txTotalGasLimit The total gass limit of the transaction (including the overhead).
            /// @param gasPerPubdataByte The price for pubdata byte in ergs.
            /// @param txEncodeLen The length of the ABI-encoding of the transaction
            function getVerifiedOperatorOverheadForTx(
                transactionIndex,
                txTotalGasLimit,
                gasPerPubdataByte,
                txEncodeLen
            ) -> ret {
                let operatorOverheadForTransaction := getOperatorOverheadForTx(transactionIndex)
                if gt(operatorOverheadForTransaction, txTotalGasLimit) {
                    assertionError("Overhead higher than gasLimit")
                }
                let txGasLimit := min(safeSub(txTotalGasLimit, operatorOverheadForTransaction, "www"), MAX_GAS_PER_TRANSACTION())

                let requiredOverhead := getTransactionUpfrontOverhead(
                    txGasLimit,
                    gasPerPubdataByte,
                    txEncodeLen
                )

                debugLog("txTotalGasLimit", txTotalGasLimit)
                debugLog("requiredOverhead", requiredOverhead)
                debugLog("operatorOverheadForTransaction", operatorOverheadForTransaction)

                // The required overhead is less than the overhead that the operator
                // has requested from the user, meaning that the operator tried to overcharge the user
                if lt(requiredOverhead, operatorOverheadForTransaction) {
                    assertionError("Operator's overhead too high")
                }

                ret := operatorOverheadForTransaction
            }

            /// @dev Function responsible for the execution of the L1->L2 transaction.
            /// @param abi The nearCall ABI. It is implicitly used as gasLimit for the call of this function.
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            function ZKSYNC_NEAR_CALL_executeL1Tx(
                abi,
                txDataOffset
            ) -> success {
                // Skipping the first word of the ABI encoding of the struct
                let innerTxDataOffset := add(txDataOffset, 0x20)
                let from := getFrom(innerTxDataOffset)
                let gasPrice := getMaxFeePerGas(innerTxDataOffset)

                debugLog("Executing L1 tx", 0)
                debugLog("from", from)
                debugLog("gasPrice", gasPrice)

                // We assume that addresses of smart contracts on zkSync and Ethereum
                // never overlap, so no need to check whether `from` is an EOA here.
                debugLog("setting tx origin", from)

                setTxOrigin(from)
                debugLog("setting gas price", gasPrice)

                setGasPrice(gasPrice)

                debugLog("execution itself", 0)

                let value := getValue(innerTxDataOffset)
                if value {
                    mintEther(from, value, true)
                }

                success := executeL1Tx(innerTxDataOffset, from)

                debugLog("Executing L1 ret", success)

                // If the success is zero, we will revert in order
                // to revert the minting of ether to the user
                if iszero(success) {
                    nearCallPanic()
                }
            }

            /// @dev Returns the ABI for nearCalls.
            /// @param gasLimit The gasLimit for this nearCall
            function getNearCallABI(gasLimit) -> ret {
                ret := gasLimit
            }

            /// @dev Used to panic from the nearCall without reverting the parent frame.
            /// If you use `revert(...)`, the error will bubble up from the near call and
            /// make the bootloader to revert as well. This method allows to exit the nearCall only.
            function nearCallPanic() {
                // Here we exhaust all the gas of the current frame.
                // This will cause the execution to panic.
                // Note, that it will cause only the inner call to panic.
                precompileCall(gas())
            }

            /// @dev Executes the `precompileCall` opcode. 
            /// Since the bootloader has no implicit meaning for this opcode,
            /// this method just burns gas.
            function precompileCall(gasToBurn) {
                // We don't care about the return value, since it is a opcode simulation 
                // and the return value doesn't have any meaning.
                let ret := verbatim_2i_1o("precompile", 0, gasToBurn)
            }
            
            /// @dev Returns the pointer to the latest returndata.
            function returnDataPtr() -> ret {
                ret := verbatim_0i_1o("get_global::ptr_return_data")
            }


            <!-- @if BOOTLOADER_TYPE=='playground_block' -->
            function ZKSYNC_NEAR_CALL_ethCall(
                abi,
                txDataOffset,
                resultPtr
            ) {
                let innerTxDataOffset := add(txDataOffset, 0x20)
                let to := getTo(innerTxDataOffset)
                let from := getFrom(innerTxDataOffset)
                
                debugLog("from: ", from)
                debugLog("to: ", to)

                switch isEOA(from)
                case true {
                    setTxOrigin(from)
                }
                default {
                    setTxOrigin(BOOTLOADER_FORMAL_ADDR())
                }

                let dataPtr := getDataPtr(innerTxDataOffset)
                markFactoryDepsForTx(innerTxDataOffset, false)
                
                let value := getValue(innerTxDataOffset)

                let success := msgValueSimulatorMimicCall(
                    to,
                    from,
                    value,
                    dataPtr
                )

                if iszero(success) {
                    // If success is 0, we need to revert
                    revertWithReason(
                        ETH_CALL_ERR_CODE(),
                        1
                    )
                }

                mstore(resultPtr, success)

                // Store results of the call in the memory.
                if success {                
                    let returnsize := returndatasize()
                    returndatacopy(0,0,returnsize)
                    return(0,returnsize)
                }

            }
            <!-- @endif -->

            /// @dev Given the pointer to the calldata, the value and to
            /// performs the call through the msg.value simulator.
            /// @param to Which contract to call
            /// @param from The `msg.sender` of the call.
            /// @param value The `value` that will be used in the call.
            /// @param dataPtr The pointer to the calldata of the transaction. It must store
            /// the length of the calldata and the calldata itself right afterwards.
            function msgValueSimulatorMimicCall(to, from, value, dataPtr) -> success {
                // Only calls to the deployer system contract are allowed to be system
                let isSystem := eq(to, CONTRACT_DEPLOYER_ADDR())

                success := mimicCallOnlyResult(
                    MSG_VALUE_SIMULATOR_ADDR(),
                    from, 
                    dataPtr,
                    0,
                    1,
                    value,
                    to,
                    isSystem
                )
            }

            /// @dev Checks whether the current frame has enough gas
            /// @dev It does not use 63/64 rule and should only be called before nearCalls. 
            function checkEnoughGas(gasToProvide) {
                debugLog("gas()", gas())
                debugLog("gasToProvide", gasToProvide)

                // Using margin of CHECK_ENOUGH_GAS_OVERHEAD gas to make sure that the operation will indeed
                // have enough gas 
                if lt(gas(), safeAdd(gasToProvide, CHECK_ENOUGH_GAS_OVERHEAD(), "cjq")) {
                    revertWithReason(NOT_ENOUGH_GAS_PROVIDED_ERR_CODE(), 0)
                }
            }

            /// Returns the block overhead to be paid, assuming a certain value of gasPerPubdata
            function getBlockOverheadGas(gasPerPubdata) -> ret {
                let computationOverhead := BLOCK_OVERHEAD_L2_GAS()
                let l1GasOverhead := BLOCK_OVERHEAD_L1_GAS()
                let l1GasPerPubdata := L1_GAS_PER_PUBDATA_BYTE()

                // Since the user specifies the amount of gas he is willing to pay for a *byte of pubdata*,
                // we need to convert the number of L1 gas needed to process the block into the equivalent number of 
                // pubdata to pay for.
                // The difference between ceil and floor division here is negligible,
                // so we prefer doing the cheaper operation for the end user
                let pubdataEquivalentForL1Gas := safeDiv(l1GasOverhead, l1GasPerPubdata, "dd")
                
                ret := safeAdd(
                    computationOverhead, 
                    safeMul(gasPerPubdata, pubdataEquivalentForL1Gas, "aa"),
                    "ab"
                )
            }

            /// @dev This method returns the overhead that should be paid upfront by a transaction.
            /// The goal of this overhead is to cover the possibility that this transaction may use up a certain
            /// limited resource per block: a single-instance circuit, runs out of pubdata available for block, etc.
            /// The transaction needs to be able to pay the same % of the costs for publishing & proving the block
            /// as the % of the block's limited resources that it can consume.
            /// @param txGasLimit The gasLimit for the transaction (note, that this limit should not include the overhead).
            /// @param gasPerPubdataByte The price for pubdata byte in gas.
            /// @param txEncodeLen The length of the ABI-encoding of the transaction
            /// @dev The % following 4 resources is taken into account when calculating the % of the block's overhead to pay.
            /// 1. The % of the maximal gas per transaction. It is assumed that `MAX_GAS_PER_TRANSACTION` gas is enough to consume all
            /// the single-instance circuits. Meaning that the transaction should pay at least txGasLimit/MAX_GAS_PER_TRANSACTION part 
            /// of the overhead.
            /// 2. Overhead for taking up the bootloader memory. The bootloader memory has a cap on its length, mainly enforced to keep the RAM requirements
            /// for the node smaller. That is, the user needs to pay a share proportional to the length of the ABI encoding of the transaction.
            /// 3. Overhead for taking up a slot for the transaction. Since each block has the limited number of transactions in it, the user must pay 
            /// at least 1/MAX_TRANSACTIONS_IN_BLOCK part of the overhead.
            /// 4. Overhead for the pubdata. It is proportional to the maximal number of pubdata the transaction could use compared to the maximal number of
            /// public data available in L1 batch. 
            function getTransactionUpfrontOverhead(
                txGasLimit,
                gasPerPubdataByte,
                txEncodeLen
            ) -> ret {
                ret := 0
                let totalBlockOverhead := getBlockOverheadGas(gasPerPubdataByte)
                debugLog("totalBlockOverhead", totalBlockOverhead)

                let overheadForCircuits := ceilDiv(
                    safeMul(totalBlockOverhead, txGasLimit, "ac"),
                    MAX_GAS_PER_TRANSACTION()
                )
                ret := max(ret, overheadForCircuits)
                debugLog("overheadForCircuits", overheadForCircuits)

                
                let overheadForLength := ceilDiv(
                    safeMul(txEncodeLen, totalBlockOverhead, "ad"),
                    BOOTLOADER_MEMORY_FOR_TXS()
                )
                ret := max(ret, overheadForLength)
                debugLog("overheadForLength", overheadForLength)

                
                let overheadForSlot := ceilDiv(
                    totalBlockOverhead,
                    MAX_TRANSACTIONS_IN_BLOCK()
                )
                ret := max(ret, overheadForSlot)
                debugLog("overheadForSlot", overheadForSlot)
            
                // In the proved block we ensure that the gasPerPubdataByte is not zero
                // to avoid the potential edge case of division by zero. In Yul, division by 
                // zero does not panic, but returns zero.
                <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                if and(iszero(gasPerPubdataByte), FORBID_ZERO_GAS_PER_PUBDATA()) {
                    assertionError("zero gasPerPubdataByte")
                }
                <!-- @endif --> 

                // We use "ceil" here for formal reasons to allow easier approach for calculating the overhead in O(1) for L1
                // calculation.
                // TODO: possibly pay for pubdata overhead
                // let maxPubdataInTx := ceilDiv(txGasLimit, gasPerPubdataByte)
                // let overheadForPubdata := ceilDiv(
                //     safeMul(maxPubdataInTx, totalBlockOverhead),
                //     MAX_PUBDATA_PER_BLOCK()
                // )
                // ret := max(ret, overheadForPubdata)
            }

            /// @dev A method where all panics in the nearCalls get to.
            /// It is needed to prevent nearCall panics from bubbling up.
            function ZKSYNC_CATCH_NEAR_CALL() {
                debugLog("ZKSYNC_CATCH_NEAR_CALL",0)
                setHook(VM_HOOK_CATCH_NEAR_CALL())
            }
            
            /// @dev Prepends the selector before the txDataOffset,
            /// preparing it to be used to call either `verify` or `execute`.
            /// Returns the pointer to the calldata.
            /// Note, that this overrides 32 bytes before the current transaction:
            function prependSelector(txDataOffset, selector) -> ret {
                
                let calldataPtr := sub(txDataOffset, 4)
                // Note, that since `mstore` stores 32 bytes at once, we need to 
                // actually store the selector in one word starting with the 
                // (txDataOffset - 32) = (calldataPtr - 28)
                mstore(sub(calldataPtr, 28), selector)

                ret := calldataPtr
            }

            /// @dev Returns the maximum of two numbers
            function max(x, y) -> ret {
                ret := y
                if gt(x, y) {
                    ret := x
                }
            }

            /// @dev Returns the minimum of two numbers
            function min(x, y) -> ret {
                ret := y
                if lt(x, y) {
                    ret := x
                }
            }

            /// @dev Returns whether x <= y
            function lte(x, y) -> ret {
                ret := or(lt(x,y), eq(x,y))
            }

            /// @dev Checks whether an address is an account
            /// @param addr The address to check
            function ensureAccount(addr) {
                mstore(0, {{RIGHT_PADDED_GET_ACCOUNT_VERSION_SELECTOR}})
                mstore(4, addr)

                let success := call(
                    gas(),
                    CONTRACT_DEPLOYER_ADDR(),
                    0,
                    0,
                    36,
                    0,
                    32
                )

                let supportedVersion := mload(0)

                if iszero(success) {
                    revertWithReason(
                        FAILED_TO_CHECK_ACCOUNT_ERR_CODE(),
                        1
                    )
                }

                // Currently only two versions are supported: 1 or 0, which basically 
                // mean whether the contract is an account or not.
                if iszero(supportedVersion) {
                    revertWithReason(
                        FROM_IS_NOT_AN_ACCOUNT_ERR_CODE(),
                        0
                    )
                }
            }

            /// @dev Checks whether an address is an EOA (i.e. has not code deployed on it)
            /// @param addr The address to check
            function isEOA(addr) -> ret {
                mstore(0, {{RIGHT_PADDED_GET_RAW_CODE_HASH_SELECTOR}})
                mstore(4, addr)
                let success := call(
                    gas(),
                    ACCOUNT_CODE_STORAGE_ADDR(),
                    0,
                    0,
                    36,
                    0,
                    32
                )

                if iszero(success) {
                    // The call to the account code storage should always succeed
                    nearCallPanic()
                }

                let rawCodeHash := mload(0)

                ret := iszero(rawCodeHash)
            }

            /// @dev Calls the `payForTransaction` method of an account
            function accountPayForTx(account, txDataOffset) -> success {
                success := callAccountMethod({{PAY_FOR_TX_SELECTOR}}, account, txDataOffset)
            }

            /// @dev Calls the `prepareForPaymaster` method of an account
            function accountPrePaymaster(account, txDataOffset) -> success {
                success := callAccountMethod({{PRE_PAYMASTER_SELECTOR}}, account, txDataOffset)
            }

            /// @dev Calls the `validateAndPayForPaymasterTransaction` method of a paymaster
            function validateAndPayForPaymasterTransaction(paymaster, txDataOffset) -> success {
                success := callAccountMethod({{VALIDATE_AND_PAY_PAYMASTER}}, paymaster, txDataOffset)
            }

            /// @dev Used to call a method with the following signature;
            /// someName( 
            ///     bytes32 _txHash,
            ///     bytes32 _suggestedSignedHash, 
            ///     Transaction calldata _transaction
            /// )
            // Note, that this method expects that the current tx hashes are already stored 
            // in the `CURRENT_L2_TX_HASHES` slots.
            function callAccountMethod(selector, account, txDataOffset) -> success {
                // Safety invariant: it is safe to override data stored under 
                // `txDataOffset`, since the account methods are called only using 
                // `callAccountMethod` or `callPostOp` methods, both of which reformat
                // the contents before innerTxDataOffset (i.e. txDataOffset + 32 bytes),
                // i.e. make sure that the position at the txDataOffset has valid value.
                let txDataWithHashesOffset := sub(txDataOffset, 64)

                // First word contains the canonical tx hash
                let currentL2TxHashesPtr := CURRENT_L2_TX_HASHES_BEGIN_BYTE()
                mstore(txDataWithHashesOffset, mload(currentL2TxHashesPtr))

                // Second word contains the suggested tx hash for verifying
                // signatures.
                currentL2TxHashesPtr := add(currentL2TxHashesPtr, 32)
                mstore(add(txDataWithHashesOffset, 32), mload(currentL2TxHashesPtr))

                // Third word contains the offset of the main tx data (it is always 96 in our case)
                mstore(add(txDataWithHashesOffset, 64), 96)

                let calldataPtr := prependSelector(txDataWithHashesOffset, selector)
                let innerTxDataOffst := add(txDataOffset, 0x20)

                let len := getDataLength(innerTxDataOffst)

                // Besides the length of the transaction itself,
                // we also require 3 words for hashes and the offset
                // of the inner tx data.
                let fullLen := add(len, 100)

                // The call itself.
                success := call(
                    gas(), // The number of gas to pass.
                    account, // The address to call.
                    0, // The `value` to pass.
                    calldataPtr, // The pointer to the calldata.
                    fullLen, // The size of the calldata, which is 4 for the selector + the actual length of the struct.
                    0, // The pointer where the returned data will be written.
                    0 // The output has size of 32 (a single bool is expected)
                )
            }

            /// @dev Calculates and saves the explorer hash and the suggested signed hash for the transaction.
            function saveTxHashes(txDataOffset) {
                let calldataPtr := prependSelector(txDataOffset, {{GET_TX_HASHES_SELECTOR}})
                let innerTxDataOffst := add(txDataOffset, 0x20)

                let len := getDataLength(innerTxDataOffst)

                // The first word is formal, but still required by the ABI
                // We also should take into account the selector.
                let fullLen := add(len, 36)

                // The call itself.
                let success := call(
                    gas(), // The number of gas to pass.
                    BOOTLOADER_UTILITIES(), // The address to call.
                    0, // The `value` to pass.
                    calldataPtr, // The pointer to the calldata.
                    fullLen, // The size of the calldata, which is 4 for the selector + the actual length of the struct.
                    CURRENT_L2_TX_HASHES_BEGIN_BYTE(), // The pointer where the returned data will be written.
                    64 // The output has size of 32 (signed tx hash and explorer tx hash are expected)
                )

                if iszero(success) {
                    revertWithReason(
                        ACCOUNT_TX_VALIDATION_ERR_CODE(),
                        1
                    )
                }

                if iszero(eq(returndatasize(), 64)) {
                    assertionError("saveTxHashes: returndata invalid")
                }
            }

            /// @dev Encodes and calls the postOp method of the contract.
            /// Note, that it *breaks* the contents of the previous transactions.
            /// @param abi The near call ABI of the call
            /// @param paymaster The address of the paymaster
            /// @param txDataOffset The offset to the ABI-encoded Transaction struct.
            /// @param txResult The status of the transaction (1 if succeeded, 0 otherwise).
            /// @param maxRefundedGas The maximum number of gas the bootloader can be refunded. 
            /// This is the `maximum` number because it does not take into account the number of gas that
            /// can be spent by the paymaster itself.
            function ZKSYNC_NEAR_CALL_callPostOp(abi, paymaster, txDataOffset, txResult, maxRefundedGas) -> success {
                // The postOp method has the following signature:
                // function postTransaction(
                //     bytes calldata _context,
                //     Transaction calldata _transaction,
                //     bytes32 _txHash,
                //     bytes32 _suggestedSignedHash,
                //     ExecutionResult _txResult,
                //     uint256 _maxRefundedGas
                // ) external payable;
                // The encoding is the following:
                // 1. Offset to the _context's content. (32 bytes)
                // 2. Offset to the _transaction's content. (32 bytes)
                // 3. _txHash (32 bytes)
                // 4. _suggestedSignedHash (32 bytes)
                // 5. _txResult (32 bytes)
                // 6. _maxRefundedGas (32 bytes)
                // 7. _context (note, that the content must be padded to 32 bytes)
                // 8. _transaction
                
                let contextLen := mload(PAYMASTER_CONTEXT_BEGIN_BYTE())
                let paddedContextLen := lengthRoundedByWords(contextLen)
                // The length of selector + the first 7 fields (with context len) + context itself.
                let preTxLen := add(228, paddedContextLen)

                let innerTxDataOffset := add(txDataOffset, 0x20)
                let calldataPtr := sub(innerTxDataOffset, preTxLen)

                {
                    let ptr := calldataPtr

                    // Selector
                    mstore(ptr, {{RIGHT_PADDED_POST_TRANSACTION_SELECTOR}})
                    ptr := add(ptr, 4)
                    
                    // context ptr
                    mstore(ptr, 192) // The context always starts at 32 * 6 position
                    ptr := add(ptr, 32)
                    
                    // transaction ptr
                    mstore(ptr, sub(innerTxDataOffset, add(calldataPtr, 4)))
                    ptr := add(ptr, 32)

                    // tx hash
                    mstore(ptr, mload(CURRENT_L2_TX_HASHES_BEGIN_BYTE()))
                    ptr := add(ptr, 32)

                    // suggested signed hash
                    mstore(ptr, mload(add(CURRENT_L2_TX_HASHES_BEGIN_BYTE(), 32)))
                    ptr := add(ptr, 32)

                    // tx result
                    mstore(ptr, txResult)
                    ptr := add(ptr, 32)

                    // maximal refunded gas
                    mstore(ptr, maxRefundedGas)
                    ptr := add(ptr, 32)

                    // storing context itself
                    memCopy(PAYMASTER_CONTEXT_BEGIN_BYTE(), ptr, add(32, paddedContextLen))
                    ptr := add(ptr, add(32, paddedContextLen))

                    // At this point, the ptr should reach the innerTxDataOffset. 
                    // If not, we have done something wrong here.
                    if iszero(eq(ptr, innerTxDataOffset)) {
                        assertionError("postOp: ptr != innerTxDataOffset")
                    }
                    
                    // no need to store the transaction as from the innerTxDataOffset starts
                    // valid encoding of the transaction
                }

                let calldataLen := safeAdd(preTxLen, getDataLength(innerTxDataOffset), "jiq")
                
                success := call(
                    gas(),
                    paymaster,
                    0,
                    calldataPtr,
                    calldataLen,
                    0,
                    0
                )
            }

            /// @dev Copies [from..from+len] to [to..to+len]
            /// Note, that len must be divisible by 32.
            function memCopy(from, to, len) {
                // Ensuring that len is always divisible by 32.
                if mod(len, 32) {
                    assertionError("Memcopy with unaligned length")
                }

                let finalFrom := safeAdd(from, len, "cka")

                for { } lt(from, finalFrom) { 
                    from := add(from, 32)
                    to := add(to, 32)
                } {
                    mstore(to, mload(from))
                }
            }

            /// @dev Validates the transaction against the senders' account.
            /// Besides ensuring that the contract agrees to a transaction,
            /// this method also enforces that the nonce has been marked as used.
            function accountValidateTx(txDataOffset) {
                // Skipping the first 0x20 word of the ABI-encoding of the struct
                let innerTxDataOffst := add(txDataOffset, 0x20)
                let from := getFrom(innerTxDataOffst)
                ensureAccount(from)

                // The nonce should be unique for each transaction.
                let nonce := getNonce(innerTxDataOffst)
                // Here we check that this nonce was not available before the validation step
                ensureNonceUsage(from, nonce, 0)

                setHook(VM_HOOK_ACCOUNT_VALIDATION_ENTERED())
                debugLog("pre-validate",0)
                debugLog("pre-validate",from)
                let success := callAccountMethod({{VALIDATE_TX_SELECTOR}}, from, txDataOffset)
                setHook(VM_HOOK_NO_VALIDATION_ENTERED())

                if iszero(success) {
                    revertWithReason(
                        ACCOUNT_TX_VALIDATION_ERR_CODE(),
                        1
                    )
                }

                ensureCorrectAccountMagic()

                // Here we make sure that the nonce is no longer available after the validation step
                ensureNonceUsage(from, nonce, 1)
            }

            /// @dev Ensures that the magic returned by the validate account method is correct
            /// It must be called right after the call of the account validation method to preserve the
            /// correct returndatasize
            function ensureCorrectAccountMagic() {
                // It is expected that the returned value is ABI-encoded bytes4 magic value
                // The Solidity always pads such value to 32 bytes and so we expect the magic to be 
                // of length 32 
                if iszero(eq(32, returndatasize())) {
                    revertWithReason(
                        ACCOUNT_RETURNED_INVALID_MAGIC_ERR_CODE(),
                        0
                    )
                }

                // Note that it is important to copy the magic even though it is not needed if the
                // `SHOULD_ENSURE_CORRECT_RETURNED_MAGIC` is false. It is never false in production
                // but it is so in fee estimation and we want to preserve as many operations as 
                // in the original operation.
                returndatacopy(0, 0, 0x20)
                let returnedValue := mload(0)
                let isMagicCorrect := eq(returnedValue, {{SUCCESSFUL_ACCOUNT_VALIDATION_MAGIC_VALUE}})

                if and(iszero(isMagicCorrect), SHOULD_ENSURE_CORRECT_RETURNED_MAGIC()) {
                    revertWithReason(
                        ACCOUNT_RETURNED_INVALID_MAGIC_ERR_CODE(),
                        0
                    )
                }
            }

            /// @dev Calls the KnownCodesStorage system contract to mark the factory dependencies of 
            /// the transaction as known.
            function markFactoryDepsForTx(innerTxDataOffset, isL1Tx) {
                debugLog("starting factory deps", 0)
                let factoryDepsPtr := getFactoryDepsPtr(innerTxDataOffset)
                let factoryDepsLength := mload(factoryDepsPtr)
                
                if gt(factoryDepsLength, MAX_NEW_FACTORY_DEPS()) {
                    assertionError("too many factory deps")
                }

                let ptr := NEW_FACTORY_DEPS_BEGIN_BYTE()
                // Selector
                mstore(ptr, {{MARK_BATCH_AS_REPUBLISHED_SELECTOR}})
                ptr := add(ptr, 32)

                // Saving whether the dependencies should be sent on L1
                // There is no need to send them for L1 transactions, since their
                // preimages are already available on L1.
                mstore(ptr, iszero(isL1Tx))
                ptr := add(ptr, 32)

                // Saving the offset to array (it is always 64)
                mstore(ptr, 64)
                ptr := add(ptr, 32)

                // Saving the array

                // We also need to include 32 bytes for the length itself
                let arrayLengthBytes := safeAdd(32, safeMul(factoryDepsLength, 32, "ag"), "af")
                // Copying factory deps array
                memCopy(factoryDepsPtr, ptr, arrayLengthBytes)
    
                let success := call(
                    gas(),
                    KNOWN_CODES_CONTRACT_ADDR(),
                    0,
                    // Shifting by 28 to start from the selector
                    add(NEW_FACTORY_DEPS_BEGIN_BYTE(), 28),
                    // 4 (selector) + 32 (send to l1 flag) + 32 (factory deps offset)+ 32 (factory deps length)
                    safeAdd(100, safeMul(factoryDepsLength, 32, "op"), "ae"),
                    0,
                    0
                )

                debugLog("factory deps success", success)

                if iszero(success) {
                    debugReturndata()
                    revertWithReason(
                        FAILED_TO_MARK_FACTORY_DEPS(),
                        1
                    )
                }
            }

            /// @dev Function responsible for executing the L1->L2 transactions.
            function executeL1Tx(innerTxDataOffset, from) -> ret {
                let to := getTo(innerTxDataOffset)
                debugLog("to", to)
                let value := getValue(innerTxDataOffset)
                debugLog("value", value)
                let dataPtr := getDataPtr(innerTxDataOffset)
                
                let dataLength := mload(dataPtr)
                let data := add(dataPtr, 32)

                ret := msgValueSimulatorMimicCall(
                    to,
                    from,
                    value,
                    dataPtr
                )

                if iszero(ret) {
                    debugReturndata()
                }
            }

            /// @dev Function responsible for the execution of the L2 transaction 
            /// @dev Returns `true` or `false` depending on whether or not the tx has reverted.
            function executeL2Tx(txDataOffset, from) -> ret {
                ret := callAccountMethod({{EXECUTE_TX_SELECTOR}}, from, txDataOffset)
                
                if iszero(ret) {
                    debugReturndata()
                }
            }

            ///
            /// zkSync-specific utilities:
            ///

            /// @dev Returns an ABI that can be used for low-level 
            /// invocations of calls and mimicCalls
            /// @param dataPtr The pointer to the calldata.
            /// @param gasPassed The number of gas to be passed with the call.
            /// @param shardId The shard id of the callee. Currently only `0` (Rollup) is supported.
            /// @param forwardingMode The mode of how the calldata is forwarded 
            /// It is possible to either pass a pointer, slice of auxheap or heap. For the
            /// bootloader purposes using heap (0) is enough.
            /// @param isConstructorCall Whether the call should contain the isConstructor flag.
            /// @param isSystemCall Whether the call should contain the isSystemCall flag.
            /// @return ret The ABI
            function getFarCallABI(
                dataPtr,
                gasPassed,
                shardId,
                forwardingMode,
                isConstructorCall,
                isSystemCall
            ) -> ret {
                let dataStart := add(dataPtr, 0x20)
                let dataLength := mload(dataPtr)

                // Skip dataOffset and memoryPage, because they are always zeros
                ret := or(ret, shl(64, dataStart))
                ret := or(ret, shl(96, dataLength))

                ret := or(ret, shl(192, gasPassed))
                ret := or(ret, shl(224, forwardingMode))
                ret := or(ret, shl(232, shardId))
                ret := or(ret, shl(240, isConstructorCall))
                ret := or(ret, shl(248, isSystemCall))
            }

            /// @dev Does mimicCall without copying the returndata.
            /// @param to Who to call
            /// @param whoToMimic The `msg.sender` of the call
            /// @param data The pointer to the calldata
            /// @param isConstructor Whether the call should contain the isConstructor flag
            /// @param isSystemCall Whether the call should contain the isSystem flag.
            /// @param extraAbi1 The first extraAbiParam
            /// @param extraAbi2 The second extraAbiParam
            /// @param extraAbi3 The third extraAbiParam
            /// @return ret 1 if the call was successful, 0 otherwise.
            function mimicCallOnlyResult(
                to,
                whoToMimic,
                data,
                isConstructor,
                isSystemCall,
                extraAbi1,
                extraAbi2,
                extraAbi3
            ) -> ret {
                let farCallAbi := getFarCallABI(
                    data,
                    gas(),
                    // Only rollup is supported for now
                    0,
                    0,
                    isConstructor,
                    isSystemCall
                )

                ret := verbatim_7i_1o("system_mimic_call", to, whoToMimic, farCallAbi, extraAbi1, extraAbi2, extraAbi3, 0) 
            }
            
            <!-- @if BOOTLOADER_TYPE=='playground_block' -->
            // Extracts the required byte from the 32-byte word.
            // 31 would mean the MSB, 0 would mean LSB.
            function getWordByte(word, byteIdx) -> ret {
                // Shift the input to the right so the required byte is LSB
                ret := shr(mul(8, byteIdx), word)
                // Clean everything else in the word
                ret := and(ret, 0xFF)
            }
            <!-- @endif -->


            /// @dev Sends an L2->L1 log.
            /// @param isService The isService flag of the call.
            /// @param key The `key` parameter of the log.
            /// @param value The `value` parameter of the log.
            function sendToL1(isService, key, value) {
                verbatim_3i_0o("to_l1", isService, key, value)
            } 
            
            /// @dev Increment the number of txs in the block
            function considerNewTx() {
                verbatim_0i_0o("increment_tx_counter")
            }

            /// @dev Set the new price per pubdata byte
            function setPricePerPubdataByte(newPrice) {
                verbatim_1i_0o("set_pubdata_price", newPrice)
            }

            /// @dev Set the new value for the tx origin context value
            function setTxOrigin(newTxOrigin) {
                let success := setContextVal({{RIGHT_PADDED_SET_TX_ORIGIN}}, newTxOrigin)

                if iszero(success) {
                    debugLog("Failed to set txOrigin", newTxOrigin)    
                    nearCallPanic()
                }
            }

            /// @dev Set the new value for the gas price value
            function setGasPrice(newGasPrice) {
                let success := setContextVal({{RIGHT_PADDED_SET_GAS_PRICE}}, newGasPrice)

                if iszero(success) {
                    debugLog("Failed to set gas price", newGasPrice)
                    nearCallPanic()
                }
            }

            /// @notice Sets the context information for the current block.
            /// @dev The SystemContext.sol system contract is responsible for validating
            /// the validity of the new block's data.
            function setNewBlock(prevBlockHash, newTimestamp, newBlockNumber, baseFee) {
                mstore(0, {{RIGHT_PADDED_SET_NEW_BLOCK_SELECTOR}})
                mstore(4, prevBlockHash)
                mstore(36, newTimestamp)
                mstore(68, newBlockNumber)
                mstore(100, baseFee)

                let success := call(
                    gas(),
                    SYSTEM_CONTEXT_ADDR(),
                    0,
                    0,
                    132,
                    0,
                    0
                )

                if iszero(success) {
                    debugLog("Failed to set new block: ", prevBlockHash)
                    debugLog("Failed to set new block: ", newTimestamp)

                    revertWithReason(FAILED_TO_SET_NEW_BLOCK_ERR_CODE(), 1)
                }
            }

            <!-- @if BOOTLOADER_TYPE=='playground_block' -->
            /// @notice Arbitrarily overrides the current block information.
            /// @dev It should NOT be available in the proved block. 
            function unsafeOverrideBlock(newTimestamp, newBlockNumber, baseFee) {
                mstore(0, {{RIGHT_PADDED_OVERRIDE_BLOCK_SELECTOR}})
                mstore(4, newTimestamp)
                mstore(36, newBlockNumber)
                mstore(68, baseFee)

                let success := call(
                    gas(),
                    SYSTEM_CONTEXT_ADDR(),
                    0,
                    0,
                    100,
                    0,
                    0
                )

                if iszero(success) {
                    debugLog("Failed to override block: ", newTimestamp)
                    debugLog("Failed to override block: ", newBlockNumber)

                    revertWithReason(FAILED_TO_SET_NEW_BLOCK_ERR_CODE(), 1)
                }
            }
            <!-- @endif -->


            // Checks whether the nonce `nonce` have been already used for 
            // account `from`. Reverts if the nonce has not been used properly.
            function ensureNonceUsage(from, nonce, shouldNonceBeUsed) {
                // INonceHolder.validateNonceUsage selector
                mstore(0, {{RIGHT_PADDED_VALIDATE_NONCE_USAGE_SELECTOR}})
                mstore(4, from)
                mstore(36, nonce)
                mstore(68, shouldNonceBeUsed)

                let success := call(
                    gas(),
                    NONCE_HOLDER_ADDR(),
                    0,
                    0,
                    100,
                    0,
                    0
                )

                if iszero(success) {
                    revertWithReason(
                        ACCOUNT_TX_VALIDATION_ERR_CODE(),
                        1
                    )
                }
            }

            /// @dev Encodes and performs a call to a method of
            /// `SystemContext.sol` system contract of the roughly the following interface:
            /// someMethod(uint256 val)
            function setContextVal(
                selector,
                value,
            ) -> ret {
                mstore(0, selector)
                mstore(4, value)

                ret := call(
                    gas(),
                    SYSTEM_CONTEXT_ADDR(),
                    0,
                    0,
                    36,
                    0,
                    0
                )
            }

            // Each of the txs have the following type:
            // struct Transaction {
            //     // The type of the transaction.
            //     uint256 txType;
            //     // The caller.
            //     uint256 from;
            //     // The callee.
            //     uint256 to;
            //     // The gasLimit to pass with the transaction. 
            //     // It has the same meaning as Ethereum's gasLimit.
            //     uint256 gasLimit;
            //     // The maximum amount of gas the user is willing to pay for a byte of pubdata.
            //     uint256 gasPerPubdataByteLimit;
            //     // The maximum fee per gas that the user is willing to pay. 
            //     // It is akin to EIP1559's maxFeePerGas.
            //     uint256 maxFeePerGas;
            //     // The maximum priority fee per gas that the user is willing to pay. 
            //     // It is akin to EIP1559's maxPriorityFeePerGas.
            //     uint256 maxPriorityFeePerGas;
            //     // The transaction's paymaster. If there is no paymaster, it is equal to 0.
            //     uint256 paymaster;
            //     // The nonce of the transaction.
            //     uint256 nonce;
            //     // The value to pass with the transaction.
            //     uint256 value;
            //     // In the future, we might want to add some
            //     // new fields to the struct. The `txData` struct
            //     // is to be passed to account and any changes to its structure
            //     // would mean a breaking change to these accounts. In order to prevent this,
            //     // we should keep some fields as "reserved".
            //     // It is also recommended that their length is fixed, since
            //     // it would allow easier proof integration (in case we will need
            //     // some special circuit for preprocessing transactions).
            //     uint256[4] reserved;
            //     // The transaction's calldata.
            //     bytes data;
            //     // The signature of the transaction.
            //     bytes signature;
            //     // The properly formatted hashes of bytecodes that must be published on L1
            //     // with the inclusion of this transaction. Note, that a bytecode has been published
            //     // before, the user won't pay fees for its republishing.
            //     bytes32[] factoryDeps;
            //     // The input to the paymaster.
            //     bytes paymasterInput;
            //     // Reserved dynamic type for the future use-case. Using it should be avoided,
            //     // But it is still here, just in case we want to enable some additional functionality.
            //     bytes reservedDynamic;
            // }

            /// @notice Asserts the equality of two values and reverts 
            /// with the appropriate error message in case it doesn't hold
            /// @param value1 The first value of the assertion
            /// @param value2 The second value of the assertion
            /// @param message The error message
            function assertEq(value1, value2, message) {
                switch eq(value1, value2) 
                    case 0 { assertionError(message) }
                    default { } 
            }

            /// @notice Makes sure that the structure of the transaction is set in accordance to its type
            /// @dev This function validates only L2 transactions, since the integrity of the L1->L2
            /// transactions is enforced by the L1 smart contracts.
            function validateTypedTxStructure(innerTxDataOffset) {
                /// Some common checks for all transactions.
                let reservedDynamicLength := getReservedDynamicBytesLength(innerTxDataOffset)
                if gt(reservedDynamicLength, 0) {
                    assertionError("non-empty reservedDynamic")
                }

                let txType := getTxType(innerTxDataOffset)
                switch txType
                    case 0 {
                        let maxFeePerGas := getMaxFeePerGas(innerTxDataOffset)
                        let maxPriorityFeePerGas := getMaxPriorityFeePerGas(innerTxDataOffset)
                        assertEq(maxFeePerGas, maxPriorityFeePerGas, "EIP1559 params wrong")
                        
                        // Here, for type 0 transactions the reserved0 field is used as a marker  
                        // whether the transaction should include chainId in its encoding.
                        assertEq(lte(getGasPerPubdataByteLimit(innerTxDataOffset), MAX_L2_GAS_PER_PUBDATA()), 1, "Gas per pubdata is wrong")
                        assertEq(getPaymaster(innerTxDataOffset), 0, "paymaster non zero")

                        <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                        assertEq(gt(getFrom(innerTxDataOffset), MAX_SYSTEM_CONTRACT_ADDR()), 1, "from in kernel space")
                        <!-- @endif -->
                        
                        assertEq(getReserved1(innerTxDataOffset), 0, "reserved1 non zero")
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getFactoryDepsBytesLength(innerTxDataOffset), 0, "factory deps non zero")
                        assertEq(getPaymasterInputBytesLength(innerTxDataOffset), 0, "paymasterInput non zero")
                    }
                    case 1 {
                        let maxFeePerGas := getMaxFeePerGas(innerTxDataOffset)
                        let maxPriorityFeePerGas := getMaxPriorityFeePerGas(innerTxDataOffset)
                        assertEq(maxFeePerGas, maxPriorityFeePerGas, "EIP1559 params wrong")

                        assertEq(lte(getGasPerPubdataByteLimit(innerTxDataOffset), MAX_L2_GAS_PER_PUBDATA()), 1, "Gas per pubdata is wrong")
                        assertEq(getPaymaster(innerTxDataOffset), 0, "paymaster non zero")

                        <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                        assertEq(gt(getFrom(innerTxDataOffset), MAX_SYSTEM_CONTRACT_ADDR()), 1, "from in kernel space")
                        <!-- @endif -->
                        
                        assertEq(getReserved0(innerTxDataOffset), 0, "reserved0 non zero")
                        assertEq(getReserved1(innerTxDataOffset), 0, "reserved1 non zero")
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getFactoryDepsBytesLength(innerTxDataOffset), 0, "factory deps non zero")
                        assertEq(getPaymasterInputBytesLength(innerTxDataOffset), 0, "paymasterInput non zero")
                    }
                    case 2 {
                        assertEq(lte(getGasPerPubdataByteLimit(innerTxDataOffset), MAX_L2_GAS_PER_PUBDATA()), 1, "Gas per pubdata is wrong")
                        assertEq(getPaymaster(innerTxDataOffset), 0, "paymaster non zero")

                        <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                        assertEq(gt(getFrom(innerTxDataOffset), MAX_SYSTEM_CONTRACT_ADDR()), 1, "from in kernel space")
                        <!-- @endif -->
                        
                        assertEq(getReserved0(innerTxDataOffset), 0, "reserved0 non zero")
                        assertEq(getReserved1(innerTxDataOffset), 0, "reserved1 non zero")
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                        assertEq(getFactoryDepsBytesLength(innerTxDataOffset), 0, "factory deps non zero")
                        assertEq(getPaymasterInputBytesLength(innerTxDataOffset), 0, "paymasterInput non zero")
                    }
                    case 113 {
                        let paymaster := getPaymaster(innerTxDataOffset)

                        assertEq(or(gt(paymaster, MAX_SYSTEM_CONTRACT_ADDR()), iszero(paymaster)), 1, "paymaster in kernel space")
                        <!-- @if BOOTLOADER_TYPE=='proved_block' -->
                        assertEq(gt(getFrom(innerTxDataOffset), MAX_SYSTEM_CONTRACT_ADDR()), 1, "from in kernel space")
                        <!-- @endif -->
                        assertEq(getReserved0(innerTxDataOffset), 0, "reserved0 non zero")
                        assertEq(getReserved1(innerTxDataOffset), 0, "reserved1 non zero")
                        assertEq(getReserved2(innerTxDataOffset), 0, "reserved2 non zero")
                        assertEq(getReserved3(innerTxDataOffset), 0, "reserved3 non zero")
                    }
                    case 255 {
                        // L1 transaction, no need to validate as it is validated on L1. 
                    }
                    default {
                        assertionError("Unknown tx type")
                    }
            }

            /// 
            /// TransactionData utilities
            /// 
            /// @dev The next methods are programmatically generated
            ///

            function getTxType(innerTxDataOffset) -> ret {
                ret := mload(innerTxDataOffset)
            }
    
            function getFrom(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 32))
            }
    
            function getTo(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 64))
            }
    
            function getGasLimit(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 96))
            }
    
            function getGasPerPubdataByteLimit(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 128))
            }
    
            function getMaxFeePerGas(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 160))
            }
    
            function getMaxPriorityFeePerGas(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 192))
            }
    
            function getPaymaster(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 224))
            }
    
            function getNonce(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 256))
            }
    
            function getValue(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 288))
            }
    
            function getReserved0(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 320))
            }
    
            function getReserved1(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 352))
            }
    
            function getReserved2(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 384))
            }
    
            function getReserved3(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 416))
            }
    
            function getDataPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 448))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getDataBytesLength(innerTxDataOffset) -> ret {
                let ptr := getDataPtr(innerTxDataOffset)
                ret := lengthRoundedByWords(mload(ptr))
            }
    
            function getSignaturePtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 480))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getSignatureBytesLength(innerTxDataOffset) -> ret {
                let ptr := getSignaturePtr(innerTxDataOffset)
                ret := lengthRoundedByWords(mload(ptr))
            }
    
            function getFactoryDepsPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 512))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getFactoryDepsBytesLength(innerTxDataOffset) -> ret {
                let ptr := getFactoryDepsPtr(innerTxDataOffset)
                ret := safeMul(mload(ptr),32, "fwop")
            }
    
            function getPaymasterInputPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 544))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getPaymasterInputBytesLength(innerTxDataOffset) -> ret {
                let ptr := getPaymasterInputPtr(innerTxDataOffset)
                ret := lengthRoundedByWords(mload(ptr))
            }
    
            function getReservedDynamicPtr(innerTxDataOffset) -> ret {
                ret := mload(add(innerTxDataOffset, 576))
                ret := add(innerTxDataOffset, ret)
            }
    
            function getReservedDynamicBytesLength(innerTxDataOffset) -> ret {
                let ptr := getReservedDynamicPtr(innerTxDataOffset)
                ret := lengthRoundedByWords(mload(ptr))
            }

            function isTxFromL1(innerTxDataOffset) -> ret {
                ret := eq(getTxType(innerTxDataOffset), L1_TX_TYPE())
            }
    
            /// This method checks that the transaction's structure is correct
            /// and tightly packed
            function validateAbiEncoding(txDataOffset) -> ret {
                if iszero(eq(mload(txDataOffset), 0x20)) {
                    assertionError("Encoding offset")
                }

                let innerTxDataOffset := add(txDataOffset, 0x20)

                let fromValue := getFrom(innerTxDataOffset)
                if iszero(validateAddress(fromValue)) {
                    assertionError("Encoding from")
                }
    
                let toValue := getTo(innerTxDataOffset)
                if iszero(validateAddress(toValue)) {
                    assertionError("Encoding to")
                }
    
                let gasLimitValue := getGasLimit(innerTxDataOffset)
                if iszero(validateUint32(gasLimitValue)) {
                    assertionError("Encoding gasLimit")
                }
    
                let gasPerPubdataByteLimitValue := getGasPerPubdataByteLimit(innerTxDataOffset)
                if iszero(validateUint32(gasPerPubdataByteLimitValue)) {
                    assertionError("Encoding gasPerPubdataByteLimit")
                }

                let maxFeePerGas := getMaxFeePerGas(innerTxDataOffset)
                if iszero(validateUint128(maxFeePerGas)) {
                    assertionError("Encoding maxFeePerGas")
                }

                let maxPriorityFeePerGas := getMaxPriorityFeePerGas(innerTxDataOffset)
                if iszero(validateUint128(maxPriorityFeePerGas)) {
                    assertionError("Encoding maxPriorityFeePerGas")
                }
    
                let paymasterValue := getPaymaster(innerTxDataOffset)
                if iszero(validateAddress(paymasterValue)) {
                    assertionError("Encoding paymaster")
                }

                let expectedDynamicLenPtr := add(innerTxDataOffset, 608)
                
                let dataLengthPos := getDataPtr(innerTxDataOffset)
                if iszero(eq(dataLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding data")
                }
                expectedDynamicLenPtr := validateBytes(dataLengthPos)
        
                let signatureLengthPos := getSignaturePtr(innerTxDataOffset)
                if iszero(eq(signatureLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding signature")
                }
                expectedDynamicLenPtr := validateBytes(signatureLengthPos)
        
                let factoryDepsLengthPos := getFactoryDepsPtr(innerTxDataOffset)
                if iszero(eq(factoryDepsLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding factoryDeps")
                }
                expectedDynamicLenPtr := validateBytes32Array(factoryDepsLengthPos)

                let paymasterInputLengthPos := getPaymasterInputPtr(innerTxDataOffset)
                if iszero(eq(paymasterInputLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding paymasterInput")
                }
                expectedDynamicLenPtr := validateBytes(paymasterInputLengthPos)

                let reservedDynamicLengthPos := getReservedDynamicPtr(innerTxDataOffset)
                if iszero(eq(reservedDynamicLengthPos, expectedDynamicLenPtr)) {
                    assertionError("Encoding reservedDynamic")
                }
                expectedDynamicLenPtr := validateBytes(reservedDynamicLengthPos)

                ret := expectedDynamicLenPtr
            }

            function getDataLength(innerTxDataOffset) -> ret {
                // To get the length of the txData in bytes, we can simply
                // get the number of fields * 32 + the length of the dynamic types
                // in bytes.
                ret := 768

                ret := safeAdd(ret, getDataBytesLength(innerTxDataOffset), "asx")        
                ret := safeAdd(ret, getSignatureBytesLength(innerTxDataOffset), "qwqa")
                ret := safeAdd(ret, getFactoryDepsBytesLength(innerTxDataOffset), "sic")
                ret := safeAdd(ret, getPaymasterInputBytesLength(innerTxDataOffset), "tpiw")
                ret := safeAdd(ret, getReservedDynamicBytesLength(innerTxDataOffset), "shy")
            }

            /// 
            /// End of programmatically generated code
            ///
    
            /// @dev Accepts an address and returns whether or not it is
            /// a valid address
            function validateAddress(addr) -> ret {
                ret := lt(addr, shl(160, 1))
            }

            /// @dev Accepts an uint32 and returns whether or not it is
            /// a valid uint32
            function validateUint32(x) -> ret {
                ret := lt(x, shl(32,1))
            }

            /// @dev Accepts an uint32 and returns whether or not it is
            /// a valid uint64
            function validateUint64(x) -> ret {
                ret := lt(x, shl(64,1))
            }

            /// @dev Accepts an uint32 and returns whether or not it is
            /// a valid uint64
            function validateUint128(x) -> ret {
                ret := lt(x, shl(128,1))
            }

            /// Validates that the `bytes` is formed correctly
            /// and returns the pointer right after the end of the bytes
            function validateBytes(bytesPtr) -> bytesEnd {
                let length := mload(bytesPtr)
                let lastWordBytes := mod(length, 32)

                switch lastWordBytes
                case 0 { 
                    // If the length is divisible by 32, then 
                    // the bytes occupy whole words, so there is
                    // nothing to validate
                    bytesEnd := safeAdd(bytesPtr, safeAdd(length, 32, "pol"), "aop") 
                }
                default {
                    // If the length is not divisible by 32, then 
                    // the last word is padded with zeroes, i.e.
                    // the last 32 - `lastWordBytes` bytes must be zeroes
                    // The easiest way to check this is to use AND operator

                    let zeroBytes := sub(32, lastWordBytes)
                    // It has its first 32 - `lastWordBytes` bytes set to 255
                    let mask := sub(shl(mul(zeroBytes,8),1),1)

                    let fullLen := lengthRoundedByWords(length)
                    bytesEnd := safeAdd(bytesPtr, safeAdd(32, fullLen, "dza"), "dzp")

                    let lastWord := mload(sub(bytesEnd, 32))

                    // If last word contains some unintended bits
                    // return 0
                    if and(lastWord, mask) {
                        assertionError("bad bytes encoding")
                    }
                }
            }

            /// @dev Accepts the pointer to the bytes32[] array length and 
            /// returns the pointer right after the array's content 
            function validateBytes32Array(arrayPtr) -> arrayEnd {
                // The bytes32[] array takes full words which may contain any content.
                // Thus, there is nothing to validate.
                let length := mload(arrayPtr)
                arrayEnd := safeAdd(arrayPtr, safeAdd(32, safeMul(length, 32, "lop"), "asa"), "sp")
            }

            ///
            /// Safe math utilities
            ///

            /// @dev Returns the multiplication of two unsigned integers, reverting on overflow.
            function safeMul(x, y, errMsg) -> ret {
                switch y
                case 0 {
                    ret := 0
                }
                default {
                    ret := mul(x, y)
                    if iszero(eq(div(ret, y), x)) {
                        assertionError(errMsg)
                    }
                }
            }

            /// @dev Returns the integer division of two unsigned integers. Reverts with custom message on
            /// division by zero. The result is rounded towards zero.
            function safeDiv(x, y, errMsg) -> ret {
                if iszero(y) {
                    assertionError(errMsg)
                }
                ret := div(x, y)
            }

            /// @dev Returns the addition of two unsigned integers, reverting on overflow.
            function safeAdd(x, y, errMsg) -> ret {
                ret := add(x, y)
                if lt(ret, x) {
                    assertionError(errMsg)
                }
            }

            /// @dev Returns the addition of two unsigned integers, reverting on overflow.
            function safeSub(x, y, errMsg) -> ret {
                if gt(y, x) {
                    assertionError(errMsg)
                }
                ret := sub(x, y)
            }

            ///
            /// Debug utilities
            ///

            /// @notice A method used to prevent optimization of x by the compiler
            /// @dev This method is only used for logging purposes 
            function nonOptimized(x) -> ret {
                // value() is always 0 in bootloader context.
                ret := add(mul(callvalue(),x),x)
            }

            /// @dev This method accepts the message and some 1-word data associated with it
            /// It triggers a VM hook that allows the server to observe the behavior of the system.
            function debugLog(msg, data) {
                storeVmHookParam(0, nonOptimized(msg))
                storeVmHookParam(1, nonOptimized(data))
                setHook(nonOptimized(VM_HOOK_DEBUG_LOG()))
            }

            /// @dev Triggers a hook that displays the returndata on the server side.
            function debugReturndata() {
                debugLog("returndataptr", returnDataPtr())
                storeVmHookParam(0, returnDataPtr()) 
                setHook(VM_HOOK_DEBUG_RETURNDATA())
            }

            /// @dev Triggers a hook that notifies the operator about the factual number of gas
            /// refunded to the user. This is to be used by the operator to derive the correct
            /// `gasUsed` in the API.
            function notifyAboutRefund(refund) {
                storeVmHookParam(0, nonOptimized(refund)) 
                setHook(VM_NOTIFY_OPERATOR_ABOUT_FINAL_REFUND())
                debugLog("refund(gas)", refund)
            }

            function notifyExecutionResult(success) {
                let ptr := returnDataPtr()
                storeVmHookParam(0, nonOptimized(success))
                storeVmHookParam(1, nonOptimized(ptr))
                setHook(VM_HOOK_EXECUTION_RESULT())

                debugLog("execution result: success", success)
                debugLog("execution result: ptr", ptr)
            }

            /// @dev Asks operator for the refund for the transaction. The function provides
            /// the operator with the leftover gas found by the bootloader. 
            /// This function is called before the refund stage, because at that point
            /// only the operator knows how close does a transaction
            /// bring us to closing the block as well as how much the transaction 
            /// should've spent on the pubdata/computation/etc.
            /// After it is run, the operator should put the expected refund
            /// into the memory slot (in the out of circuit execution).
            /// Since the slot after the transaction is not touched,
            /// this slot can be used in the in-circuit VM out of box.
            function askOperatorForRefund(gasLeft) {
                storeVmHookParam(0, nonOptimized(gasLeft)) 
                setHook(VM_HOOK_ASK_OPERATOR_FOR_REFUND())
            }
            
            /// 
            /// Error codes used for more correct diagnostics from the server side.
            /// 

            function ETH_CALL_ERR_CODE() -> ret {
                ret := 0
            }

            function ACCOUNT_TX_VALIDATION_ERR_CODE() -> ret {
                ret := 1
            }

            function FAILED_TO_CHARGE_FEE_ERR_CODE() -> ret {
                ret := 2
            }

            function FROM_IS_NOT_AN_ACCOUNT_ERR_CODE() -> ret {
                ret := 3
            }

            function FAILED_TO_CHECK_ACCOUNT_ERR_CODE() -> ret {
                ret := 4
            }

            function UNACCEPTABLE_GAS_PRICE_ERR_CODE() -> ret {
                ret := 5
            }

            function FAILED_TO_SET_NEW_BLOCK_ERR_CODE() -> ret {
                ret := 6
            }

            function PAY_FOR_TX_FAILED_ERR_CODE() -> ret {
                ret := 7
            }

            function PRE_PAYMASTER_PREPARATION_FAILED_ERR_CODE() -> ret {
                ret := 8
            }

            function PAYMASTER_VALIDATION_FAILED_ERR_CODE() -> ret {
                ret := 9
            }

            function FAILED_TO_SEND_FEES_TO_THE_OPERATOR() -> ret {
                ret := 10
            }

            function UNACCEPTABLE_PUBDATA_PRICE_ERR_CODE() -> ret {
                ret := 11
            }

            function TX_VALIDATION_FAILED_ERR_CODE() -> ret {
                ret := 12
            }

            function MAX_PRIORITY_FEE_PER_GAS_GREATER_THAN_MAX_FEE_PER_GAS() -> ret {
                ret := 13
            }

            function BASE_FEE_GREATER_THAN_MAX_FEE_PER_GAS() -> ret {
                ret := 14
            }

            function PAYMASTER_RETURNED_INVALID_CONTEXT() -> ret {
                ret := 15
            }

            function PAYMASTER_RETURNED_CONTEXT_IS_TOO_LONG() -> ret {
                ret := 16
            }

            function ASSERTION_ERROR() -> ret {
                ret := 17
            }

            function FAILED_TO_MARK_FACTORY_DEPS() -> ret {
                ret := 18
            }

            function TX_VALIDATION_OUT_OF_GAS() -> ret {
                ret := 19
            }

            function NOT_ENOUGH_GAS_PROVIDED_ERR_CODE() -> ret {
                ret := 20
            }

            function ACCOUNT_RETURNED_INVALID_MAGIC_ERR_CODE() -> ret {
                ret := 21
            }

            function PAYMASTER_RETURNED_INVALID_MAGIC_ERR_CODE() -> ret {
                ret := 22
            }

            function MINT_ETHER_FAILED_ERR_CODE() -> ret {
                ret := 23
            }

            /// @dev Accepts a 1-word literal and returns its length in bytes
            /// @param str A string literal
            function getStrLen(str) -> len {
                len := 0
                // The string literals are stored left-aligned. Thus, 
                // In order to get the length of such string,
                // we shift it to the left (remove one byte to the left) until 
                // no more non-empty bytes are left.
                for {} str {str := shl(8, str)} {
                    len := add(len, 1)
                }
            }   

            // Selector of the errors used by the "require" statements in Solidity
            // and the one that can be parsed by our server.
            function GENERAL_ERROR_SELECTOR() -> ret {
                ret := {{REVERT_ERROR_SELECTOR}}
            }

            /// @notice Reverts with assertion error with the provided error string literal.
            function assertionError(err) {
                let ptr := 0

                // The first byte indicates that the revert reason is an assertion error
                mstore8(ptr, ASSERTION_ERROR())
                ptr := add(ptr, 1)

                // Then, we need to put the returndata in a way that is easily parsable by our 
                // servers
                mstore(ptr, GENERAL_ERROR_SELECTOR())
                ptr := add(ptr, 4)
                
                // Then, goes the "data offset". It is has constant value of 32.
                mstore(ptr, 32)
                ptr := add(ptr, 32)
                
                // Then, goes the length of the string:
                mstore(ptr, getStrLen(err))
                ptr := add(ptr, 32)
                
                // Then, we put the actual string
                mstore(ptr, err)
                ptr := add(ptr, 32)

                revert(0, ptr)
            }

            /// @notice Accepts an error code and whether there is a need to copy returndata
            /// @param errCode The code of the error
            /// @param sendReturnData A flag of whether or not the returndata should be used in the 
            /// revert reason as well. 
            function revertWithReason(errCode, sendReturnData) {
                let returndataLen := 1
                mstore8(0, errCode)

                if sendReturnData {
                    // Here we ignore all kinds of limits on the returned data,
                    // since the `revert` will happen shortly after.
                    returndataLen := add(returndataLen, returndatasize())
                    returndatacopy(1, 0, returndatasize())
                }
                revert(0, returndataLen)
            }

            function VM_HOOK_ACCOUNT_VALIDATION_ENTERED() -> ret {
                ret := 0
            }
            function VM_HOOK_PAYMASTER_VALIDATION_ENTERED() -> ret {
                ret := 1
            }
            function VM_HOOK_NO_VALIDATION_ENTERED() -> ret {
                ret := 2
            }
            function VM_HOOK_VALIDATION_STEP_ENDED() -> ret {
                ret := 3
            }
            function VM_HOOK_TX_HAS_ENDED() -> ret {
                ret := 4
            }
            function VM_HOOK_DEBUG_LOG() -> ret {
                ret := 5
            }
            function VM_HOOK_DEBUG_RETURNDATA() -> ret {
                ret := 6
            }
            function VM_HOOK_CATCH_NEAR_CALL() -> ret {
                ret := 7
            }
            function VM_HOOK_ASK_OPERATOR_FOR_REFUND() -> ret {
                ret := 8
            }
            function VM_NOTIFY_OPERATOR_ABOUT_FINAL_REFUND() -> ret {
                ret := 9
            }
            function VM_HOOK_EXECUTION_RESULT() -> ret {
                ret := 10
            }

            // Need to prevent the compiler from optimizing out similar operations, 
            // which may have different meaning for the offline debugging 
            function unoptimized(val) -> ret {
                ret := add(val, callvalue())
            }

            /// @notice Triggers a VM hook. 
            /// The server will recognize it and output corresponding logs.
            function setHook(hook) {
                mstore(VM_HOOK_PTR(), unoptimized(hook))
            }   

            /// @notice Sets a value to a param of the vm hook.
            /// @param paramId The id of the VmHook parameter.
            /// @param value The value of the parameter.
            /// @dev This method should be called before triggering the VM hook itself.
            /// @dev It is the responsibility of the caller to never provide
            /// paramId smaller than the VM_HOOK_PARAMS()
            function storeVmHookParam(paramId, value) {
                let offset := add(VM_HOOK_PARAMS_OFFSET(), mul(32, paramId))
                mstore(offset, unoptimized(value))
            }
        }
    }
}
