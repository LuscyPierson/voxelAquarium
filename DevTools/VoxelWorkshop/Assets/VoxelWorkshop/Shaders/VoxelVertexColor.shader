// Vertex-coloured blocks lit roughly like the app: a sun from above and in front, plus soft sky light.
// Vertex alpha 0 marks a glowing block, drawn at full colour regardless of light.
Shader "VoxelWorkshop/VertexColor"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 color : COLOR;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 normal : TEXCOORD0;
                float4 color : COLOR;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                o.color = v.color;
                #ifndef UNITY_COLORSPACE_GAMMA
                o.color.rgb = GammaToLinearSpace(v.color.rgb);
                #endif
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 n = normalize(i.normal);
                float3 sun = normalize(float3(-0.3, 0.85, -0.45));
                float lit = 0.42 + 0.18 * (0.5 + 0.5 * n.y) + 0.5 * saturate(dot(n, sun));
                return fixed4(i.color.rgb * lerp(1.0, lit, i.color.a), 1);
            }
            ENDCG
        }
    }
}
