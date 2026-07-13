# Security Policy

## Modelo de seguridad

Novara asume una separacion de responsabilidades entre owner, keeper, guardian y treasury.
El owner configura parametros estructurales, el keeper ejecuta operaciones programadas y el
guardian puede pausar componentes o activar controles de emergencia.

## Invariantes esperadas

- La suma de pesos activos de mint debe ser 10.000 bps.
- Cada emision debe respetar la composicion objetivo dentro de la tolerancia configurada.
- Las redenciones ordinarias deben liquidar componentes prorrata contra el supply vigente.
- Los feeds de precio deben estar activos, dentro de limites y no vencidos.
- Los cambios de peso deben pasar por una ventana de planificacion antes de consolidarse.
- Las pausas de componentes deben bloquear flujos dependientes del componente pausado.

## Validacion automatizada

La validacion local y de CI compila todos los contratos Vyper y ejecuta tests Python con
Titanoboa sobre una EVM local. Los tests cubren flujos principales de composicion, emision,
redencion, rebalanceo, pausas y sustitucion finalizada.

## Alcance de revision

El alcance primario esta en `src/`, con especial atencion a la boveda, token, oraculo, registro,
planner de rebalance, controles de riesgo y modulos de lectura. Los mocks de `src/mocks/` existen
solo para pruebas locales.

## Dependencias

Las dependencias Python estan fijadas en `requirements.txt`. Dependabot cubre paquetes pip y
GitHub Actions.

## Reportes

Los reportes internos deben incluir impacto, precondiciones, secuencia de reproduccion,
componentes afectados y recomendacion de mitigacion. No incluir secretos ni datos de usuarios en
issues publicos.
