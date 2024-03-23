// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8;

abstract contract Initializable {
    bool public initialized;

    /**
     * @dev Already initialized.
     */
    error InvalidInitialization();

    modifier initializer() {
        if (initialized) {
            revert InvalidInitialization();
        }

        initialized = true;
        _;
    }
}
