/**
 * src/index.ts — Bootstrap de TreePruning CMS
 *
 * Siembra mensajes i18n y parámetros de configuración al primer arranque.
 * Es idempotente: no inserta duplicados si los datos ya existen.
 */

// ─── Tipos ────────────────────────────────────────────────────────────────────

interface MensajeInput {
  codigo: string;
  texto: string;
  categoria: string;
  activo: boolean;
}

interface ParametroInput {
  clave: string;
  valor: string;
}

// ─── Datos semilla — Mensajes ─────────────────────────────────────────────────

const MENSAJES: MensajeInput[] = [

  // ── Notificaciones FCM ──────────────────────────────────────────────────────
  {
    codigo:    'notifications.pruning-scheduled.title.es',
    texto:     'Poda programada',
    categoria: 'notifications',
    activo:    true,
  },
  {
    codigo:    'notifications.pruning-scheduled.title.en',
    texto:     'Pruning scheduled',
    categoria: 'notifications',
    activo:    true,
  },
  {
    codigo:    'notifications.pruning-scheduled.body.es',
    texto:     'Tu poda preventiva está programada para el {{date}}.',
    categoria: 'notifications',
    activo:    true,
  },
  {
    codigo:    'notifications.pruning-scheduled.body.en',
    texto:     'Your preventive pruning is scheduled for {{date}}.',
    categoria: 'notifications',
    activo:    true,
  },

  // ── Éxito — Podas ───────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.PRUNING.SCHEDULED',
    texto:     'Poda preventiva programada exitosamente.',
    categoria: 'success.pruning',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.PRUNING.LIST',
    texto:     'Podas consultadas exitosamente.',
    categoria: 'success.pruning',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.PRUNING.GET',
    texto:     'Poda consultada exitosamente.',
    categoria: 'success.pruning',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.PRUNING.PHOTO_URL',
    texto:     'URL de foto generada exitosamente.',
    categoria: 'success.pruning',
    activo:    true,
  },

  // ── Éxito — PQR ─────────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.PQR.CREATED',
    texto:     'PQR creado exitosamente.',
    categoria: 'success.pqr',
    activo:    true,
  },

  // ── Éxito — Familias ────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.FAMILY.LIST',
    texto:     'Familias consultadas exitosamente.',
    categoria: 'success.family',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.FAMILY.GET',
    texto:     'Familia consultada exitosamente.',
    categoria: 'success.family',
    activo:    true,
  },

  // ── Éxito — Managers ────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.MANAGER.LIST',
    texto:     'Gestores consultados exitosamente.',
    categoria: 'success.manager',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.MANAGER.GET',
    texto:     'Gestor consultado exitosamente.',
    categoria: 'success.manager',
    activo:    true,
  },

  // ── Éxito — Personas ────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.PERSON.LIST',
    texto:     'Personas consultadas exitosamente.',
    categoria: 'success.person',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.PERSON.GET',
    texto:     'Persona consultada exitosamente.',
    categoria: 'success.person',
    activo:    true,
  },

  // ── Éxito — Programaciones ──────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.PROGRAMMING.LIST',
    texto:     'Programaciones consultadas exitosamente.',
    categoria: 'success.programming',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.PROGRAMMING.GET',
    texto:     'Programación consultada exitosamente.',
    categoria: 'success.programming',
    activo:    true,
  },

  // ── Éxito — Cuadrillas ──────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.QUADRILLE.LIST',
    texto:     'Cuadrillas consultadas exitosamente.',
    categoria: 'success.quadrille',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.QUADRILLE.GET',
    texto:     'Cuadrilla consultada exitosamente.',
    categoria: 'success.quadrille',
    activo:    true,
  },

  // ── Éxito — Sectores ────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.SECTOR.LIST',
    texto:     'Sectores consultados exitosamente.',
    categoria: 'success.sector',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.SECTOR.GET',
    texto:     'Sector consultado exitosamente.',
    categoria: 'success.sector',
    activo:    true,
  },

  // ── Éxito — Estados ─────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.STATUS.LIST',
    texto:     'Estados consultados exitosamente.',
    categoria: 'success.status',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.STATUS.GET',
    texto:     'Estado consultado exitosamente.',
    categoria: 'success.status',
    activo:    true,
  },

  // ── Éxito — Tipos ───────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.TYPE.LIST',
    texto:     'Tipos consultados exitosamente.',
    categoria: 'success.type',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.TYPE.GET',
    texto:     'Tipo consultado exitosamente.',
    categoria: 'success.type',
    activo:    true,
  },

  // ── Éxito — Árboles ─────────────────────────────────────────────────────────
  {
    codigo:    'SUCCESS.TREE.LIST',
    texto:     'Árboles consultados exitosamente.',
    categoria: 'success.tree',
    activo:    true,
  },
  {
    codigo:    'SUCCESS.TREE.GET',
    texto:     'Árbol consultado exitosamente.',
    categoria: 'success.tree',
    activo:    true,
  },

  // ── Errores — Autenticación ─────────────────────────────────────────────────
  {
    codigo:    'ERROR.AUTH.UNAUTHORIZED',
    texto:     'No tiene autorización para realizar esta acción.',
    categoria: 'error.auth',
    activo:    true,
  },
  {
    codigo:    'ERROR.AUTH.FORBIDDEN',
    texto:     'Acceso denegado. No cuenta con los permisos necesarios.',
    categoria: 'error.auth',
    activo:    true,
  },

  // ── Errores — Podas ─────────────────────────────────────────────────────────
  {
    codigo:    'ERROR.PRUNING.PLANNED_DATE_NULL',
    texto:     'La fecha de programación es obligatoria.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.PLANNED_DATE_PAST',
    texto:     'La fecha de programación no puede ser una fecha pasada.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.PLANNED_DATE_BEYOND_HORIZON',
    texto:     'La fecha de programación supera el horizonte máximo permitido.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.TREE_NOT_FOUND',
    texto:     'No se encontró el árbol especificado.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.TREE_ALREADY_SCHEDULED',
    texto:     'El árbol ya tiene una poda programada.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.QUADRILLE_NOT_FOUND',
    texto:     'No se encontró la cuadrilla especificada.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.TYPE_NOT_FOUND',
    texto:     'No se encontró el tipo de poda especificado.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.STATUS_NOT_FOUND',
    texto:     'No se encontró el estado de poda especificado.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.PHOTO_NOT_AVAILABLE',
    texto:     'La foto de la poda no está disponible.',
    categoria: 'error.pruning',
    activo:    true,
  },
  {
    codigo:    'ERROR.PRUNING.PHOTO_READ_FAILED',
    texto:     'No se pudo leer la foto de la poda.',
    categoria: 'error.pruning',
    activo:    true,
  },

  // ── Errores — Storage ───────────────────────────────────────────────────────
  {
    codigo:    'ERROR.STORAGE.UPLOAD_FAILED',
    texto:     'No se pudo subir el archivo. Intente nuevamente.',
    categoria: 'error.storage',
    activo:    true,
  },
  {
    codigo:    'ERROR.STORAGE.PRESIGN_FAILED',
    texto:     'No se pudo generar el enlace de acceso al archivo.',
    categoria: 'error.storage',
    activo:    true,
  },

  // ── Errores — Genéricos ─────────────────────────────────────────────────────
  {
    codigo:    'ERROR.GENERIC.INTERNAL',
    texto:     'Ocurrió un error interno. Por favor intente más tarde.',
    categoria: 'error.generic',
    activo:    true,
  },
  {
    codigo:    'ERROR.GENERIC.RESOURCE_NOT_FOUND',
    texto:     'El recurso solicitado no existe.',
    categoria: 'error.generic',
    activo:    true,
  },

  // ── Técnicos ────────────────────────────────────────────────────────────────
  // (solo se usan en logs del backend, no se muestran al usuario)
  {
    codigo:    'TECHNICAL.ERROR.GENERIC.INTERNAL',
    texto:     'Internal server error. Check application logs.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.GENERIC.RESOURCE_NOT_FOUND',
    texto:     'Requested resource does not exist.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.PLANNED_DATE_NULL',
    texto:     'plannedDate is null or default date.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.PLANNED_DATE_PAST',
    texto:     'plannedDate is in the past.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.PLANNED_DATE_BEYOND_HORIZON',
    texto:     'plannedDate exceeds the allowed planning horizon.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.TREE_NOT_FOUND',
    texto:     'Tree not found with provided ID.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.TREE_ALREADY_SCHEDULED',
    texto:     'Tree already has a scheduled pruning.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.QUADRILLE_NOT_FOUND',
    texto:     'Quadrille not found with provided ID.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.TYPE_NOT_FOUND',
    texto:     'PruningType not found with name from parameter catalog.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.STATUS_NOT_FOUND',
    texto:     'PruningStatus not found with name from parameter catalog.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.PHOTO_NOT_AVAILABLE',
    texto:     'photographicReportPath is null or blank.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.PRUNING.PHOTO_READ_FAILED',
    texto:     'Failed to read photo from MinIO.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.STORAGE.UPLOAD_FAILED',
    texto:     'MinIO upload failed.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.ERROR.STORAGE.PRESIGN_FAILED',
    texto:     'MinIO presigned URL generation failed.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.VALIDATION.PRUNING.TREES_REQUIRED',
    texto:     'trees list is null or empty.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.VALIDATION.PRUNING.TREES_MAX',
    texto:     'trees list exceeds maximum allowed count.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.VALIDATION.PRUNING.QUADRILLE_REQUIRED',
    texto:     'quadrilleId is null or default UUID.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.VALIDATION.PRUNING.PHOTO_TOO_LONG',
    texto:     'photographicRecordPath exceeds allowed length.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.VALIDATION.PRUNING.PHOTO_MAX_SIZE',
    texto:     'photo file size exceeds 5 MB.',
    categoria: 'technical',
    activo:    true,
  },
  {
    codigo:    'TECHNICAL.VALIDATION.PRUNING.PHOTO_INVALID_FORMAT',
    texto:     'photo MIME type is not allowed (jpeg/png/webp only).',
    categoria: 'technical',
    activo:    true,
  },
];

// ─── Datos semilla — Parámetros ───────────────────────────────────────────────

const PARAMETROS: ParametroInput[] = [
  {
    // Horizonte máximo de programación de podas (en meses desde hoy).
    // El validador rechaza fechas más allá de: hoy + horizonte.
    clave: 'podas.horizonte-meses',
    valor: '12',
  },
  {
    // Nombre del tipo de poda que se asigna al crear una poda preventiva.
    // Debe coincidir exactamente con treepruning.type.name en la BD.
    clave: 'podas.tipo-creacion-preventiva',
    valor: 'Poda Preventiva',
  },
  {
    // Nombre del estado inicial de una poda recién programada.
    // Debe coincidir exactamente con treepruning.status.name en la BD.
    clave: 'podas.estado-creacion-default',
    valor: 'Planeada',
  },
];

// ─── Bootstrap ────────────────────────────────────────────────────────────────

export default {

  register(/* { strapi } */) {},

  async bootstrap({ strapi }) {
    await seedCollection(strapi, 'api::mensaje.mensaje', 'codigo', MENSAJES);
    await seedCollection(strapi, 'api::parametro.parametro', 'clave', PARAMETROS);
  },
};

// ─── Helper ───────────────────────────────────────────────────────────────────

async function seedCollection(
  strapi: any,
  uid: string,
  uniqueField: string,
  items: Record<string, any>[],
) {
  let inserted = 0;
  let skipped  = 0;

  for (const item of items) {
    try {
      // Buscar por el campo único para no duplicar
      const existing = await strapi.documents(uid).findFirst({
        filters: { [uniqueField]: { $eq: item[uniqueField] } },
        status: 'published',
      });

      if (existing) {
        skipped++;
        continue;
      }

      await strapi.documents(uid).create({
        data:   item,
        status: 'published',
      });

      inserted++;
    } catch (err: any) {
      strapi.log.warn(
        `[SEED] Error insertando ${uid} [${item[uniqueField]}]: ${err?.message}`,
      );
    }
  }

  strapi.log.info(
    `[SEED] ${uid}: ${inserted} insertados, ${skipped} ya existían.`,
  );
}
