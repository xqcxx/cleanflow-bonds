// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

library TokenUtils {
    error TokenTransferFailed();

    function safeTransfer(IERC20 token, address recipient, uint256 amount) internal {
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transfer, (recipient, amount)));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) revert TokenTransferFailed();
    }

    function safeTransferFrom(IERC20 token, address sender, address recipient, uint256 amount) internal {
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)));
        if (!success || (result.length != 0 && !abi.decode(result, (bool)))) revert TokenTransferFailed();
    }
}
