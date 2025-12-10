// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Verificacion de usuarios aptos para volar
/// @notice Mantiene un registro on-chain de si un usuario puede o no reservar vuelos,
///         en base a credenciales verificadas off-chain (Aries/Indy en produccion).
contract UserVerification {
    address public issuer; // entidad autorizada a registrar permisos (mock de Aries/backend)

    mapping(address => bool) private _canRide;

    event IssuerChanged(address indexed previousIssuer, address indexed newIssuer);
    event RiderPermissionSet(address indexed user, bool canRide);

    constructor(address initialIssuer) {
        require(initialIssuer != address(0), "Issuer invalido");
        issuer = initialIssuer;
        emit IssuerChanged(address(0), initialIssuer);
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "No autorizado: solo issuer");
        _;
    }

    /// @notice Permite cambiar el issuer autorizado (por ejemplo rotacion de backend/agent).
    function setIssuer(address newIssuer) external onlyIssuer {
        require(newIssuer != address(0), "Issuer invalido");
        address previous = issuer;
        issuer = newIssuer;
        emit IssuerChanged(previous, newIssuer);
    }

    /// @dev Mock de verificacion de credencial SSI.
    /// En una integracion real, Aries/Indy verificaria la firma, esquema, version, revocacion, etc.
    function verifyCredentialSignature(
        bytes memory credential,
        string memory schemaName,
        string memory schemaVersion
    ) internal pure returns (bool) {
        // Silenciar warnings
        credential;
        schemaName;
        schemaVersion;

        // MOCK: siempre true. En el futuro aqui podrías chequear un hash,
        // un identificador de credencial, o delegar a otro contrato.
        return true;
    }

    /// @dev Mock de extraccion del campo "can_ride" de la credencial.
    /// En produccion, Aries haria esta extraccion y pasaria solo el resultado.
    function extractCredentialCanRide(
        bytes memory credential
    ) internal pure returns (bool) {
        // MOCK: por simplicidad, si hay algun byte, asumimos can_ride = true.
        // Esto es solo para mantener la firma; en produccion esto no existiria on-chain.
        return credential.length > 0;
    }

    /// @notice Registra o actualiza el permiso de un usuario para volar,
    ///         en base a una credencial verificada off-chain.
    /// @param user Address del usuario en la red Besu.
    /// @param userCredential Credencial SSI mock (por ejemplo Rider_Credential v1.0).
    /// @return canRide Decision final de si el usuario puede volar.
    function setRiderPermissionWithCredential(
        address user,
        bytes memory userCredential
    ) public onlyIssuer returns (bool canRide) {
        require(user != address(0), "Usuario invalido");

        // 1. Verificar la credencial (mock)
        require(
            verifyCredentialSignature(
                userCredential,
                "Rider_Credential",
                "1.0"
            ),
            "Credencial de usuario invalida"
        );

        // 2. Extraer campo can_ride (mock)
        bool extractedCanRide = extractCredentialCanRide(userCredential);

        // 3. Guardar resultado
        _canRide[user] = extractedCanRide;
        emit RiderPermissionSet(user, extractedCanRide);

        return extractedCanRide;
    }

    /// @notice Registra directamente la decision canRide para un usuario.
    /// @dev Esta funcion representa el caso en el que Aries/Indy ya decidio
    ///      todo off-chain y solo se refleja el resultado en la blockchain.
    function setRiderPermission(
        address user,
        bool canRide
    ) public onlyIssuer {
        require(user != address(0), "Usuario invalido");
        _canRide[user] = canRide;
        emit RiderPermissionSet(user, canRide);
    }

    /// @notice Devuelve true si el usuario esta autorizado para volar.
    function canUserRide(address user) external view returns (bool) {
        return _canRide[user];
    }
}

