# Mutual recursive strategic merge for objects and arrays with "name"
def strategic_merge($b; $o):
  # helper for arrays
  def strategic_merge_array($b; $o):
    ($b | map(select(type=="object" and has("name")))) as $named_base
    | ($o | map(select(type=="object" and has("name")))) as $named_override
    | (
        # merge objects with same name
        ($named_base + $named_override
          | group_by(.name)
          | map(reduce .[] as $item ({}; strategic_merge(.; $item)))
        )
        # append non-named elements from override
        + ($o | map(select(.name? | not)))
      );

  # main logic
  if ($b | type) == "object" and ($o | type) == "object" then
    ($b + $o)
    | with_entries(
        .value = (
          if ($b[.key]? | type) == "object" and ($o[.key]? | type) == "object" then
            strategic_merge($b[.key]; $o[.key])
          elif ($b[.key]? | type) == "array" and ($o[.key]? | type) == "array" then
            strategic_merge_array($b[.key]; $o[.key])
          else
            .value
          end
        )
      )
  else
    $o
  end;

.spec as $spec
  | "storage" as $volume
  | {
      apiVersion: "v1",
      spec: {
        securityContext: {
          runAsUser: 0,
          runAsGroup: 0,
          fsGroup: 0,
          fsGroupChangePolicy: "Always"
        },
        containers: [
          {
            name: "keycloak",
            image: $spec.image,
            imagePullSecrets:
            $spec.imagePullSecrets,
            env: [
              {
                name: "KC_CACHE",
                value: "local"
              },
              {
                name: "KC_DB",
                value: $spec.db.vendor
              },
              {
                name: "KC_DB_URL_HOST",
                value: $spec.db.host
              },
              {
                name: "KC_DB_URL_DATABASE",
                value: $spec.db.database
              },
              {
                name: "KC_DB_USERNAME",
                valueFrom: {
                  secretKeyRef: $spec.db.usernameSecret
                }
              },
              {
                name: "KC_DB_PASSWORD",
                valueFrom: {
                  secretKeyRef: $spec.db.passwordSecret
                }
              }
            ],
            volumeMounts: [
              {
                name: $volume,
                mountPath: $volumeAt
              }
            ]
          }
        ],
        volumes: [
          {
            name: $volume,
            persistentVolumeClaim: {
              claimName: $pvc
            }
          }
        ],
        nodeSelector: {
          "kubernetes.io/hostname": $node
        }
      }
    } as $base
  | ($spec.unsupported?.podTemplate // {}) as $patch
  | strategic_merge($base; $patch)
  | .spec.containers = (.spec.containers | map(.name = $name))
