// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @notice Interfaz mínima del contrato de verificación de usuarios.
interface IUserVerification {
    function canUserRide(address user) external view returns (bool);
}

/// @notice Interfaz mínima del contrato de gestión de vertiports.
interface IVertiportManagement {
    function checkLandingAvailability(string memory vertiportId) external view returns (bool);

    function updateVertiportState(
        string memory vertiportId,
        bytes memory vertiportCredential,
        int256 airstripDelta,
        int256 parkingDelta
    ) external;
}

/// @notice Interfaz mínima del contrato de gestión de eVTOLs.
interface IEVTOLManagement {
    function isAvailable(uint256 id) external view returns (bool);
    function assignToTrip(uint256 id, string memory tripId) external;
    function startTrip(uint256 id) external;
    function completeTrip(uint256 id, string memory destinationVertiportId) external;
}

/// @title Contrato de reserva de viajes
/// @notice Orquesta la verificacion de usuario, asignacion de eVTOL y actualizacion
///         de vertiports para registrar y seguir viajes.
contract FlightReservation {
    enum TripStatus {
        REQUESTED,
        CONFIRMED,
        IN_PROGRESS,
        COMPLETED,
        CANCELLED
    }

    struct Trip {
        string id;
        address rider;
        string originVertiportId;
        string destinationVertiportId;
        uint256 evtolId;
        TripStatus status;
        uint256 createdAt;
        bool exists;
    }

    IUserVerification public userVerification;
    IVertiportManagement public vertiportManagement;
    IEVTOLManagement public evtolManagement;

    // Sencillo control de acceso: solo admin puede orquestar reservas
    address public admin;

    mapping(string => Trip) private trips;

    event TripCreated(
        string indexed tripId,
        address indexed rider,
        string originVertiportId,
        string destinationVertiportId,
        uint256 evtolId
    );

    event TripStatusUpdated(
        string indexed tripId,
        TripStatus previousStatus,
        TripStatus newStatus
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "No autorizado: solo admin");
        _;
    }

    constructor(
        address userVerificationAddress,
        address vertiportManagementAddress,
        address evtolManagementAddress
    ) {
        require(userVerificationAddress != address(0), "UserVerification invalido");
        require(vertiportManagementAddress != address(0), "VertiportManagement invalido");
        require(evtolManagementAddress != address(0), "EVTOLManagement invalido");

        admin = msg.sender;
        userVerification = IUserVerification(userVerificationAddress);
        vertiportManagement = IVertiportManagement(vertiportManagementAddress);
        evtolManagement = IEVTOLManagement(evtolManagementAddress);
    }

    /// @notice Permite cambiar el admin (por ejemplo, rotacion de backend).
    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Admin invalido");
        admin = newAdmin;
    }

    /// @notice Crea una reserva y asigna un eVTOL en un solo paso.
    /// @dev Simplificacion: asumimos que backend ya eligio el eVTOL concreto.
    /// @param tripId Id logico del viaje (unico).
    /// @param rider Address del usuario que va a viajar.
    /// @param originVertiportId Id del vertiport de origen.
    /// @param destinationVertiportId Id del vertiport de destino.
    /// @param evtolId Id del eVTOL asignado.
    /// @param userCredential Credencial SSI mock del usuario (ya verificada off-chain).
    /// @param originVertiportCredential Credencial SSI mock del vertiport origen.
    /// @param evtolCredential Credencial SSI mock del eVTOL.
    function createReservation(
        string memory tripId,
        address rider,
        string memory originVertiportId,
        string memory destinationVertiportId,
        uint256 evtolId,
        bytes memory userCredential,
        bytes memory originVertiportCredential,
        bytes memory evtolCredential
    ) public onlyAdmin {
        require(bytes(tripId).length > 0, "tripId vacio");
        require(!trips[tripId].exists, "Trip ya existe");
        require(rider != address(0), "Rider invalido");
        require(bytes(originVertiportId).length > 0, "Origen vacio");
        require(bytes(destinationVertiportId).length > 0, "Destino vacio");
        require(evtolId != 0, "EVTOL invalido");

        // 1. Verificar que el usuario esta autorizado para volar.
        //    Teoricamente userCredential se verifico off-chain, aqui solo usamos el resultado.
        //    Si quieres seguir el PDF al pie de la letra, puedes hacer que UserVerification
        //    tenga una funcion verifyUserEligibility(userCredential) que devuelva bool.
        require(
            userVerification.canUserRide(rider),
            "Usuario no autorizado para reservar"
        );
        userCredential; // silenciar warning; mock

        // 2. Verificar disponibilidad en vertiport de origen
        require(
            vertiportManagement.checkLandingAvailability(originVertiportId),
            "Sin capacidad en vertiport origen"
        );
        originVertiportCredential; // silenciar warning; mock

        // 3. Verificar que el eVTOL esta disponible
        require(
            evtolManagement.isAvailable(evtolId),
            "EVTOL no disponible"
        );
        evtolCredential; // silenciar warning; mock

        // 4. Asignar el eVTOL al viaje (PARKED -> EXPECTING)
        evtolManagement.assignToTrip(evtolId, tripId);

        // 5. Registrar viaje con estado CONFIRMED
        Trip storage t = trips[tripId];
        t.id = tripId;
        t.rider = rider;
        t.originVertiportId = originVertiportId;
        t.destinationVertiportId = destinationVertiportId;
        t.evtolId = evtolId;
        t.status = TripStatus.CONFIRMED;
        t.createdAt = block.timestamp;
        t.exists = true;

        emit TripCreated(tripId, rider, originVertiportId, destinationVertiportId, evtolId);
        emit TripStatusUpdated(tripId, TripStatus.REQUESTED, TripStatus.CONFIRMED);
    }

    /// @notice Inicia el viaje (CONFIRMED -> IN_PROGRESS).
    /// @dev Simplificacion: se libera 1 parking en vertiport origen cuando el EVTOL despega.
    /// @param tripId Id del viaje.
    /// @param originVertiportCredential Credencial SSI mock del vertiport origen.
    function startTrip(
        string memory tripId,
        bytes memory originVertiportCredential
    ) public onlyAdmin {
        Trip storage t = trips[tripId];
        require(t.exists, "Trip no encontrada");
        require(t.status == TripStatus.CONFIRMED, "Estado de trip invalido");

        // 1. Cambiar estado del EVTOL (EXPECTING -> IN_USE)
        evtolManagement.startTrip(t.evtolId);

        // 2. Actualizar capacidad del vertiport de origen.
        //    Simplificacion: liberamos 1 parking (eVTOL deja de ocuparlo al salir).
        //    airstripDelta = 0 (no modelamos pistas en detalle aqui).
        vertiportManagement.updateVertiportState(
            t.originVertiportId,
            originVertiportCredential,
            0,
            int256(1)  // +1 parking libre
        );

        TripStatus previous = t.status;
        t.status = TripStatus.IN_PROGRESS;

        emit TripStatusUpdated(tripId, previous, t.status);
    }

    /// @notice Completa el viaje (IN_PROGRESS -> COMPLETED).
    /// @dev Simplificacion: se ocupa 1 parking en vertiport destino cuando el EVTOL llega.
    /// @param tripId Id del viaje.
    /// @param destinationVertiportCredential Credencial SSI mock del vertiport destino.
    function completeTrip(
        string memory tripId,
        bytes memory destinationVertiportCredential
    ) public onlyAdmin {
        Trip storage t = trips[tripId];
        require(t.exists, "Trip no encontrada");
        require(t.status == TripStatus.IN_PROGRESS, "Estado de trip invalido");

        // 1. Actualizar EVTOL (IN_USE -> PARKED en vertiport destino)
        evtolManagement.completeTrip(t.evtolId, t.destinationVertiportId);

        // 2. Actualizar capacidad del vertiport de destino:
        //    el EVTOL ahora ocupa un parking => -1 parking libre.
        vertiportManagement.updateVertiportState(
            t.destinationVertiportId,
            destinationVertiportCredential,
            0,
            int256(-1) // -1 parking libre
        );

        TripStatus previous = t.status;
        t.status = TripStatus.COMPLETED;

        emit TripStatusUpdated(tripId, previous, t.status);
    }

    /// @notice Cancela un viaje antes de que inicie (CONFIRMED -> CANCELLED).
    /// @dev No tocamos aqui los recursos fisicos; esa logica puedes ampliarla despues.
    function cancelTrip(string memory tripId) public onlyAdmin {
        Trip storage t = trips[tripId];
        require(t.exists, "Trip no encontrada");
        require(
            t.status == TripStatus.CONFIRMED || t.status == TripStatus.REQUESTED,
            "No se puede cancelar en este estado"
        );

        TripStatus previous = t.status;
        t.status = TripStatus.CANCELLED;

        emit TripStatusUpdated(tripId, previous, t.status);
    }

    /// @notice Devuelve la informacion de un viaje.
    function getTrip(
        string memory tripId
    ) public view returns (Trip memory) {
        Trip memory t = trips[tripId];
        require(t.exists, "Trip no encontrada");
        return t;
    }
}

