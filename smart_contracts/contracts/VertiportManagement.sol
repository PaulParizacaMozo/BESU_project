// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Gestión de Vertiports
/// @notice Mantiene la capacidad y disponibilidad de pistas y parkings
///         para cada vertiport registrado en la red.
contract VertiportManagement {
    struct VertiportState {
        string id;
        uint256 n_airstrip;        // pistas totales
        uint256 n_parkings;        // parkings totales
        uint256 n_free_airstrip;   // pistas libres actuales
        uint256 n_parkings_free;   // parkings libres actuales
        bool exists;
    }

    // Tabla de vertiports indexada por su identificador
    mapping(string => VertiportState) private vertiports;

    event VertiportRegistered(
        string indexed vertiportId,
        uint256 n_airstrip,
        uint256 n_parkings
    );

    event VertiportUpdated(
        string indexed vertiportId,
        uint256 n_free_airstrip,
        uint256 n_parkings_free
    );

    /// @dev Mock de verificación de credencial.
    /// En una integración real, la verificación SSI se hace off-chain (Aries/Indy)
    /// y aquí solo se usaría algún identificador/resultado.
    function verifyCredentialSignature(
        bytes memory credential,
        string memory schemaName,
        string memory schemaVersion
    ) internal pure returns (bool) {
        // Silenciar warnings de parámetros no usados
        credential;
        schemaName;
        schemaVersion;

        // MOCK: siempre true. En el futuro, aquí se podría chequear un hash,
        // un campo, o delegar a otro contrato.
        return true;
    }

    /// @notice Registra un nuevo vertiport en la red.
    /// @param vertiportId Identificador lógico del vertiport.
    /// @param n_airstrip Número total de pistas de aterrizaje.
    /// @param n_parkings Número total de parkings.
    /// @param vertiportCredential Credencial SSI mock del vertiport.
    function registerVertiport(
        string memory vertiportId,
        uint256 n_airstrip,
        uint256 n_parkings,
        bytes memory vertiportCredential
    ) public {
        require(
            verifyCredentialSignature(
                vertiportCredential,
                "Port_Credential",
                "4.0"
            ),
            "Credencial de vertiport invalida"
        );

        VertiportState storage existing = vertiports[vertiportId];
        require(!existing.exists, "Vertiport ya registrado");
        require(
            n_airstrip > 0 || n_parkings > 0,
            "Capacidad invalida"
        );

        VertiportState storage port = vertiports[vertiportId];
        port.id = vertiportId;
        port.n_airstrip = n_airstrip;
        port.n_parkings = n_parkings;
        port.n_free_airstrip = n_airstrip;
        port.n_parkings_free = n_parkings;
        port.exists = true;

        emit VertiportRegistered(vertiportId, n_airstrip, n_parkings);
        emit VertiportUpdated(vertiportId, port.n_free_airstrip, port.n_parkings_free);
    }

    /// @notice Actualiza la disponibilidad de pistas y parkings de un vertiport.
    /// @dev Los deltas pueden ser positivos (liberar recursos) o negativos (ocupar).
    /// @param vertiportId Identificador del vertiport.
    /// @param vertiportCredential Credencial SSI mock del vertiport.
    /// @param airstripDelta Cambio en pistas libres (int, puede ser negativo).
    /// @param parkingDelta Cambio en parkings libres (int, puede ser negativo).
    function updateVertiportState(
        string memory vertiportId,
        bytes memory vertiportCredential,
        int256 airstripDelta,
        int256 parkingDelta
    ) public {
        // Verificar credencial del vertiport
        require(
            verifyCredentialSignature(
                vertiportCredential,
                "Port_Credential",
                "4.0"
            ),
            "Credencial de vertiport invalida"
        );

        VertiportState storage port = vertiports[vertiportId];
        require(port.exists, "Vertiport no encontrado");

        // Actualizar pistas libres respetando limites
        if (airstripDelta > 0) {
            port.n_free_airstrip += uint256(airstripDelta);
            require(
                port.n_free_airstrip <= port.n_airstrip,
                "Limite de pistas excedido"
            );
        } else if (airstripDelta < 0) {
            uint256 delta = uint256(-airstripDelta);
            require(
                port.n_free_airstrip >= delta,
                "No hay pistas libres suficientes"
            );
            port.n_free_airstrip -= delta;
        }

        // Actualizar parkings libres respetando limites
        if (parkingDelta > 0) {
            port.n_parkings_free += uint256(parkingDelta);
            require(
                port.n_parkings_free <= port.n_parkings,
                "Limite de parkings excedido"
            );
        } else if (parkingDelta < 0) {
            uint256 deltaP = uint256(-parkingDelta);
            require(
                port.n_parkings_free >= deltaP,
                "No hay parkings libres suficientes"
            );
            port.n_parkings_free -= deltaP;
        }

        emit VertiportUpdated(vertiportId, port.n_free_airstrip, port.n_parkings_free);
    }

    /// @notice Indica si hay al menos una pista y un parking libres.
    function checkLandingAvailability(
        string memory vertiportId
    ) public view returns (bool) {
        VertiportState storage port = vertiports[vertiportId];
        if (!port.exists) {
            return false;
        }
        return (port.n_free_airstrip > 0 && port.n_parkings_free > 0);
    }

    /// @notice Devuelve el estado completo de un vertiport.
    function getVertiportState(
        string memory vertiportId
    ) public view returns (VertiportState memory) {
        VertiportState memory port = vertiports[vertiportId];
        require(port.exists, "Vertiport no encontrado");
        return port;
    }
}

