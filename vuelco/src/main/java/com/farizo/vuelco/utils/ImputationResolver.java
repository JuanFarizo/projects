package com.farizo.vuelco.utils;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

public class ImputationResolver {
    private static final Map<Pattern, String> reglas = new LinkedHashMap<>();

    static {
        // Impuestos
        reglas.put(Pattern.compile("SIRCREB", Pattern.CASE_INSENSITIVE), "Sircreb");
        reglas.put(Pattern.compile("IMP\\.?\\s*DEB", Pattern.CASE_INSENSITIVE), "Impuesto al debito");
        reglas.put(Pattern.compile("IMP\\.?\\s*CRE|DEV\\.IMP\\.CRED", Pattern.CASE_INSENSITIVE), "Impuesto al credito");
        reglas.put(Pattern.compile("\\bIVA\\b", Pattern.CASE_INSENSITIVE), "IVA");
        reglas.put(Pattern.compile("PERCEP.*IVA", Pattern.CASE_INSENSITIVE), "Percep IVA");

        // Comisiones
        reglas.put(Pattern.compile("COMISION|COM\\. GESTION", Pattern.CASE_INSENSITIVE), "Comisiones y gastos");

        // Sueldos — specific "acreditamiento de haberes" must come before the generic ACREDITAMIENTO rule
        reglas.put(Pattern.compile("ACREDITAMIENTO.*HABERES|ACRED\\..*HABERES", Pattern.CASE_INSENSITIVE),
                "Pago de Sueldos");

        // Deudores por ventas
        reglas.put(Pattern.compile(
                "ACREDITAMIENTO|NAVE|CREDITO TRANSFERENCIA|TRANSFERENCIA DE TERCEROS|TRANSFERENCIAS CASH",
                Pattern.CASE_INSENSITIVE), "Deudores por ventas");
        reglas.put(Pattern.compile("FIRSTDATA|AMERICAN EXPRESS|CABAL|TARJETA NARANJA", Pattern.CASE_INSENSITIVE),
                "Deudores por ventas");

        // Proveedores
        reglas.put(Pattern.compile("PAGO A PROVEEDORES|TRF INMED PROVEED|PAGO DE SERVICIOS|ANULAC\\. ACRED",
                Pattern.CASE_INSENSITIVE), "Proveedores");

        // Sueldos
        reglas.put(Pattern.compile("HABERES|SUELDOS", Pattern.CASE_INSENSITIVE), "Pago de Sueldos");

        // AFIP
        reglas.put(Pattern.compile("AFIP", Pattern.CASE_INSENSITIVE), "Pago AFIP");

        // Tarjeta corporativa
        reglas.put(Pattern.compile("PAGO VISA EMPRESA", Pattern.CASE_INSENSITIVE), "Pago Tarjeta Corporativa");

        // Pr√©stamos
        reglas.put(Pattern.compile("CUOTA DE PRESTAMO", Pattern.CASE_INSENSITIVE), "Pago prestamos");

        // FCI
        reglas.put(Pattern.compile("FIMA PREMIUM|SUSCRIPCION FIMA|RESCATE FIMA", Pattern.CASE_INSENSITIVE), "FCI");

        // Transferencias internas
        reglas.put(Pattern.compile("TRANSF INMED CP", Pattern.CASE_INSENSITIVE), "Trans. Entre cuentas");
    }

    public static String resolver(String descripcion) {
        for (Map.Entry<Pattern, String> regla : reglas.entrySet()) {
            if (regla.getKey().matcher(descripcion).find()) {
                return regla.getValue();
            }
        }
        return "Otro"; // fallback si no matchea ninguna regla
    }
}
