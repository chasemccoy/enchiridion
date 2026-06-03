import { db } from '@db/index';
import { type RecordSelect } from '@db/schema';
import type { APIResponse } from '@shared/types/api';
import { containmentPredicateSlugs, descriptionPredicateSlugs } from '@shared/types';

const familyPredicateSlugs = [...containmentPredicateSlugs, ...descriptionPredicateSlugs];

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
            in: familyPredicateSlugs,
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
                    in: familyPredicateSlugs,
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
                    in: familyPredicateSlugs,
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
            in: familyPredicateSlugs,
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
                    in: familyPredicateSlugs,
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
