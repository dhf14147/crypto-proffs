// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";s


// CriptoMoonWolfToken: Un token ERC20 con funciones de minting, burning, fees, airdrop, pausa y control de acceso basado en roles.
contract CriptoMoonWolfToken is ERC20, AccessControl, Pausable, ReentrancyGuard {
    // Roles para controlar permisos en el contrato.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEV_ROLE = keccak256("DEV_ROLE");

    // Suministro máximo del token.
    uint256 public constant maxSupply = 1000000 * 1e18;

    // Dirección de la billetera de tesorería donde se enviará la tasa de transferencia.
    address public treasuryWallet;

    // Tasa fija de transferencia para la tesorería (1%).
    uint256 public constant treasuryFeePercentage = 1;

    // Tasa fija de transferencia para quema (1%).
    uint256 public constant burnFeePercentage = 1;

    // Evento que se emite cuando se mintean nuevos tokens.
    event Mint(address indexed to, uint256 amount);

    // Evento que se emite cuando se queman tokens.
    event Burn(address indexed from, uint256 amount);

    // Evento que se emite cuando se actualiza la billetera de tesorería.
    event TreasuryWalletUpdated(address newTreasuryWallet);

    // Constructor: Inicializa el token con nombre, símbolo, suministro inicial y billetera de tesorería.
    constructor(
        string memory name_,
        string memory symbol_,
        address treasuryWallet_
    ) ERC20(name_, symbol_) {
        require(
            treasuryWallet_ != address(0),
            "CriptoMoonWolfToken: treasury wallet cannot be zero address"
        );

        // Asignar roles iniciales al creador del contrato.
        _grantRole(ADMIN_ROLE, msg.sender); // ADMIN_ROLE para operaciones administrativas.
        _grantRole(DEV_ROLE, msg.sender); // DEV_ROLE para desarrolladores.

        // ADMIN_ROLE también tiene permisos para gestionar roles.
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(DEV_ROLE, ADMIN_ROLE);

        // Inicializar billetera de tesorería.
        treasuryWallet = treasuryWallet_; // Asignar la billetera de tesorería al parámetro proporcionado.
    }

    // Función para pausar el contrato. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    // Función para reanudar el contrato. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // Función para mintear nuevos tokens. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function mint(address to, uint256 amount) external onlyRole(ADMIN_ROLE) whenNotPaused {
        // Verificar que el suministro total después del mint no exceda el suministro máximo.
        require(
            totalSupply() + amount <= maxSupply,
            "CriptoMoonWolfToken: max supply exceeded"
        );
        _mint(to, amount);
        emit Mint(to, amount); // Emitir evento para registrar la operación.
    }

    // Función para quemar tokens. Cualquier usuario puede quemar sus propios tokens.
    function burn(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount); // Emitir evento para registrar la operación.
    }

    // Función para asignar un rol a una cuenta. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function assignRole(
        bytes32 role,
        address account
    ) external onlyRole(ADMIN_ROLE) {
        grantRole(role, account);
    }

    // Función para revocar un rol de una cuenta. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function removeRole(
        bytes32 role,
        address account
    ) external onlyRole(ADMIN_ROLE) {
        revokeRole(role, account);
    }

    // Función para realizar un airdrop. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function airdrop(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(
            recipients.length == amounts.length,
            "CriptoMoonWolfToken: recipients and amounts length mismatch"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            // Verificar que el suministro total no exceda el máximo después de cada transferencia.
            require(
                totalSupply() + amounts[i] <= maxSupply,
                "CriptoMoonWolfToken: max supply exceeded"
            );
            _mint(recipients[i], amounts[i]);
            emit Mint(recipients[i], amounts[i]); // Emitir evento para registrar la operación.
        }
    }

    // Función para recuperar tokens ERC20 enviados accidentalmente al contrato. (otros tokens, no el del propio contrato)
    // Solo accesible para cuentas con el rol ADMIN_ROLE.
    function recoverERC20(
        address tokenAddress,
        uint256 amount,
        address to
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        require(
            tokenAddress != address(this),
            "CriptoMoonWolfToken: cannot recover native token"
        );
        IERC20(tokenAddress).transfer(to, amount);
    }

    // Función para recuperar tokens nativos del contrato enviados por error.
    // Solo accesible para cuentas con el rol ADMIN_ROLE.
    function recoverNativeTokens(
        uint256 amount,
        address to
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        uint256 contractBalance = balanceOf(address(this));
        require(
            amount <= contractBalance,
            "CriptoMoonWolfToken: insufficient contract balance"
        );
        _transfer(address(this), to, amount);
    }

    // Función para actualizar la billetera de tesorería. Solo accesible para cuentas con el rol ADMIN_ROLE.
    function updateTreasuryWallet(
        address newTreasuryWallet
    ) external onlyRole(ADMIN_ROLE) {
        require(
            newTreasuryWallet != address(0),
            "CriptoMoonWolfToken: treasury wallet cannot be zero address"
        );
        treasuryWallet = newTreasuryWallet;
        emit TreasuryWalletUpdated(newTreasuryWallet);
    }

    function transfer(address to, uint256 amount)
        public
        override
        whenNotPaused
        returns (bool)
    {
        _transferWithFees(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        whenNotPaused
        returns (bool)
    {
        uint256 currentAllowance = allowance(from, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(from, _msgSender(), currentAllowance - amount);

        _transferWithFees(from, to, amount);
        return true;
    }

    
    function _transferWithFees(address from, address to, uint256 amount)
        internal
    {
        // Excluir a la billetera de tesorería de las fees.
        if (from == treasuryWallet || to == treasuryWallet) {
            super._transfer(from, to, amount);
            return;
        }

        uint256 treasuryAmount = (amount * treasuryFeePercentage) / 100;
        uint256 burnAmount = (amount * burnFeePercentage) / 100;
        uint256 amountAfterFee = amount - burnAmount - treasuryAmount;

        // Transferir la parte de la tasa a la billetera de tesorería.
        if (treasuryAmount > 0) {
            super._transfer(from, treasuryWallet, treasuryAmount);
        }

        // Quemar la parte correspondiente.
        if (burnAmount > 0) {
            _burn(from, burnAmount);
        }

        // Transferir el resto al destinatario.
        super._transfer(from, to, amountAfterFee);
    }

    // Función para aprobar a un spender para gastar tokens en nombre del usuario.
    // Override para proteger con whenNotPaused para evitar aprobaciones durante una pausa.
    function approve(address spender, uint256 amount)
        public
        override
        whenNotPaused
        returns (bool)
    {
        return super.approve(spender, amount);
    }



    // Consideraciones de seguridad:
    // 1. ADMIN_ROLE es ahora el rol más poderoso. Las cuentas con este rol pueden otorgar o revocar cualquier otro rol.
    // 2. ADMIN_ROLE tiene permisos administrativos para mintear, realizar airdrops y gestionar roles.
    // 3. DEV_ROLE puede ser utilizado para funcionalidades específicas de desarrollo.
    // 4. Es recomendable transferir ADMIN_ROLE a un contrato multisig o a un sistema descentralizado para evitar riesgos de centralización.
    // 5. Asegúrate de que las cuentas con ADMIN_ROLE sean confiables, ya que tienen control directo sobre el suministro de tokens y la gestión de roles.
}
