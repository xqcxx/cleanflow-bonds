// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library CleanFlowTypes {
    bytes32 internal constant MANDATE_TYPEHASH = keccak256(
        "ExecutionMandate(address trader,address executor,address recipient,bytes32 poolId,bool zeroForOne,uint128 amountIn,uint128 minAmountOut,uint160 sqrtPriceLimitX96,uint64 deadline,uint64 nonce,uint8 warrantyTier)"
    );

    enum AuthorizationKind {
        None,
        Protected,
        Inventory
    }

    enum WarrantyState {
        None,
        Pending,
        Challenged,
        Cleared,
        Slashed
    }

    struct ExecutionMandate {
        address trader;
        address executor;
        address recipient;
        bytes32 poolId;
        bool zeroForOne;
        uint128 amountIn;
        uint128 minAmountOut;
        uint160 sqrtPriceLimitX96;
        uint64 deadline;
        uint64 nonce;
        uint8 warrantyTier;
    }

    struct Authorization {
        AuthorizationKind kind;
        address executor;
        address trader;
        bytes32 executionId;
        bytes32 poolId;
        uint128 amountIn;
        bool zeroForOne;
        bool consumed;
        bool recorded;
    }

    struct Warranty {
        address trader;
        address executor;
        uint128 reservedBond;
        uint64 openedAtBlock;
        uint64 resolutionBlock;
        uint64 snapshotBlock;
        uint64 sequence;
        bytes32 evidenceHash;
        WarrantyState state;
    }

    function hashMandate(ExecutionMandate memory mandate) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MANDATE_TYPEHASH,
                mandate.trader,
                mandate.executor,
                mandate.recipient,
                mandate.poolId,
                mandate.zeroForOne,
                mandate.amountIn,
                mandate.minAmountOut,
                mandate.sqrtPriceLimitX96,
                mandate.deadline,
                mandate.nonce,
                mandate.warrantyTier
            )
        );
    }
}
