import { db } from '@db/index';
import { type RecordSelect } from '@db/schema';
import type { APIResponse } from '@shared/types/api';
import { ALL_PREDICATES } from '@shared/predicates';

// Get all canonical predicate slugs that are containment or description type
const containmentOrDescriptionSlugs = ALL_PREDICATES.filter(
  (p) => p.canonical && (p.type === 'containment' || p.type === 'description'),
).map((p) => p.slug);

export const getFamilyTree = async (recordId: RecordSelect['id']) => {
  const family = await db.query.records.findFirst({
    where: {
      id: recordId,
    },
    columns: {
      id: true,
      title: true,
      slug: true,
      recordCreatedAt: true,
    },
    with: {
      outgoingLinks: {
        where: {
          predicate: {
            in: containmentOrDescriptionSlugs,
          },
        },
        columns: {
          predicate: true,
        },
        with: {
          target: {
            columns: {
              id: true, // Parent
              title: true,
              slug: true,
              recordCreatedAt: true,
            },
            with: {
              outgoingLinks: {
                where: {
                  predicate: {
                    in: containmentOrDescriptionSlugs,
                  },
                },
                columns: {
                  predicate: true,
                },
                with: {
                  target: {
                    columns: {
                      id: true, // Grandparent
                      title: true,
                      slug: true,
                      recordCreatedAt: true,
                    },
                  },
                },
              },
              incomingLinks: {
                where: {
                  predicate: {
                    in: containmentOrDescriptionSlugs,
                  },
                },
                columns: {
                  predicate: true,
                },
                with: {
                  source: {
                    columns: {
                      id: true, // Siblings
                      title: true,
                      slug: true,
                      recordCreatedAt: true,
                    },
                  },
                },
              },
            },
          },
        },
      },
      incomingLinks: {
        where: {
          predicate: {
            in: containmentOrDescriptionSlugs,
          },
        },
        columns: {
          predicate: true,
        },
        with: {
          source: {
            columns: {
              id: true, // Children
              title: true,
              slug: true,
              recordCreatedAt: true,
            },
            with: {
              outgoingLinks: {
                where: {
                  predicate: {
                    in: containmentOrDescriptionSlugs,
                  },
                },
                columns: {
                  predicate: true,
                },
                with: {
                  target: {
                    columns: {
                      id: true, // Grandchildren
                      title: true,
                      slug: true,
                      recordCreatedAt: true,
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  });

  return family;
};

export type GetFamilyTreeAPIResponse = APIResponse<typeof getFamilyTree>;
