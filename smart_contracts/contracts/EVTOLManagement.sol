// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Gestión de estados de eVTOLs
/// @notice Mantiene el estado operativo y la ubicación actual de cada eVTOL.
contract EVTOLManagement {
    enum EVTOLState {
        PARKED,      // estacionado en un vertiport
        EXPECTING,   // asignado a un viaje, en preparación
        IN_USE,      // vuelo en curso
        MAINTENANCE  // fuera de servicio por mantenimiento
    }

    struct EVTOL {
        uint256 id;
        EVTOLState state;
        string currentVertiportId;
        string activeTripId; // vacío cuando no hay viaje activo
        bool exists;
    }

    mapping(uint256 => EVTOL) private evtols;

    event EVTOLRegistered(
        uint256 indexed id,
        string currentVertiportId
    );

    event EVTOLStateChanged(
        uint256 indexed id,
        EVTOLState previousState,
        EVTOLState newState,
        string currentVertiportId,
        string activeTripId
    );

    /// @dev Mock de verificación de credencial SSI para eVTOL.
    function verifyCredentialSignature(
        bytes memory credential,
        string memory schemaName,
        string memory schemaVersion
    ) internal pure returns (bool) {
        // Silenciar warnings
        credential;
        schemaName;
        schemaVersion;

        // MOCK: siempre true
        return true;
    }

    /// @notice Registra un nuevo eVTOL en estado PARKED en un vertiport.
    /// @param id Identificador único del eVTOL.
    /// @param initialVertiportId Vertiport donde está inicialmente.
    /// @param evtolCredential Credencial SSI mock del eVTOL.
    function registerEVTOL(
        uint256 id,
        string memory initialVertiportId,
        bytes memory evtolCredential
    ) public {
        require(!evtols[id].exists, "EVTOL ya registrado");

        require(
            verifyCredentialSignature(
                evtolCredential,
                "Evtol_Crede",
                "3.0"
            ),
            "Credencial de EVTOL invalida"
        );

        EVTOL storage e = evtols[id];
        e.id = id;
        e.state = EVTOLState.PARKED;
        e.currentVertiportId = initialVertiportId;
        e.activeTripId = "";
        e.exists = true;

        emit EVTOLRegistered(id, initialVertiportId);
        emit EVTOLStateChanged(id, EVTOLState.PARKED, EVTOLState.PARKED, initialVertiportId, "");
    }

    /// @notice Asigna un eVTOL a un viaje y lo pone en estado EXPECTING.
    /// @param id Id del eVTOL.
    /// @param tripId Id del viaje asignado.
    function assignToTrip(
        uint256 id,
        string memory tripId
    ) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.PARKED, "EVTOL no esta PARKED");
        require(bytes(e.activeTripId).length == 0, "Ya tiene viaje activo");
        require(bytes(tripId).length > 0, "tripId vacio");

        EVTOLState previous = e.state;
        e.state = EVTOLState.EXPECTING;
        e.activeTripId = tripId;

        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    /// @notice Marca que el eVTOL inicia el vuelo para el viaje asignado.
    /// @param id Id del eVTOL.
    function startTrip(uint256 id) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.EXPECTING, "EVTOL no esta EXPECTING");
        require(bytes(e.activeTripId).length > 0, "No hay viaje activo");

        EVTOLState previous = e.state;
        e.state = EVTOLState.IN_USE;

        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    /// @notice Completa el viaje y estaciona el eVTOL en el vertiport destino.
    /// @param id Id del eVTOL.
    /// @param destinationVertiportId Vertiport donde queda estacionado al final.
    function completeTrip(
        uint256 id,
        string memory destinationVertiportId
    ) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.IN_USE, "EVTOL no esta IN_USE");
        require(bytes(e.activeTripId).length > 0, "No hay viaje activo");

        EVTOLState previous = e.state;

        // Actualizar ubicación y estado
        e.state = EVTOLState.PARKED;
        e.currentVertiportId = destinationVertiportId;
        e.activeTripId = "";

        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    /// @notice Pone el eVTOL en mantenimiento (no puede aceptar viajes).
    /// @param id Id del eVTOL.
    function setMaintenance(uint256 id) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.PARKED, "Solo PARKED puede ir a MAINTENANCE");
        require(bytes(e.activeTripId).length == 0, "No debe tener viaje activo");

        EVTOLState previous = e.state;
        e.state = EVTOLState.MAINTENANCE;

        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    /// @notice Saca al eVTOL de mantenimiento y lo deja PARKED.
    /// @param id Id del eVTOL.
    function finishMaintenance(uint256 id) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.MAINTENANCE, "EVTOL no esta en MAINTENANCE");

        EVTOLState previous = e.state;
        e.state = EVTOLState.PARKED;

        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    /// @notice Devuelve la info de un eVTOL.
    function getEVTOL(uint256 id) public view returns (EVTOL memory) {
        EVTOL memory e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        return e;
    }

    /// @notice Devuelve true si el eVTOL esta PARKED y sin viaje activo (apto para asignar).
    function isAvailable(uint256 id) public view returns (bool) {
        EVTOL storage e = evtols[id];
        if (!e.exists) return false;
        if (e.state != EVTOLState.PARKED) return false;
        if (bytes(e.activeTripId).length != 0) return false;
        return true;
    }
}

