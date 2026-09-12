"use client";

import { useRef, useState } from "react";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import type { ProductImage } from "@/lib/types";

// Direct browser -> Storage upload, same "Storage is a separate,
// already-authenticated path" precedent as the rider KYC upload (Sprint 2)
// -- the Edge Function never sees the image bytes, only the resulting
// public URL (migrations/020's bucket comment). Path convention
// `{shopId}/{productId}/{random}.{ext}` matches that migration's
// `(storage.foldername(name))[1]` = shop_id RLS check.
export function ImageManager({
  shopId,
  productId,
  images,
  onChange,
}: {
  shopId: string;
  productId: string;
  images: ProductImage[];
  onChange: (images: ProductImage[]) => void;
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    setUploading(true);
    try {
      const supabase = createClient();
      const ext = file.name.includes(".") ? file.name.split(".").pop() : "jpg";
      const path = `${shopId}/${productId}/${crypto.randomUUID()}.${ext}`;

      const { error: uploadError } = await supabase.storage.from("product-images").upload(path, file);
      if (uploadError) throw uploadError;

      const {
        data: { publicUrl },
      } = supabase.storage.from("product-images").getPublicUrl(path);

      const { data } = await apiFetchClient<{ data: ProductImage }>(`/v1/shop/shops/${shopId}/products/${productId}/images`, {
        method: "POST",
        body: JSON.stringify({ imageUrl: publicUrl, sortOrder: images.length }),
      });
      onChange([...images, data]);
      toast.success("Photo added");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not upload photo");
    } finally {
      setUploading(false);
    }
  }

  async function deleteImage(id: string) {
    try {
      await apiFetchClient(`/v1/shop/shops/${shopId}/products/${productId}/images/${id}`, { method: "DELETE" });
      onChange(images.filter((img) => img.id !== id));
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not remove photo");
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-3">
        {images.map((img) => (
          <div key={img.id} className="group relative h-24 w-24 overflow-hidden rounded-md border">
            {/* eslint-disable-next-line @next/next/no-img-element -- Storage
                URLs are dynamic, per-shop, and this small an admin-only
                gallery doesn't need next/image's optimization pipeline. */}
            <img src={img.imageUrl} alt="" className="h-full w-full object-cover" />
            <button
              type="button"
              onClick={() => deleteImage(img.id)}
              className="absolute right-1 top-1 rounded bg-black/60 px-1.5 py-0.5 text-xs text-white opacity-0 transition-opacity group-hover:opacity-100"
            >
              Remove
            </button>
          </div>
        ))}
      </div>

      <div>
        <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={handleFileChange} />
        <Button type="button" variant="outline" disabled={uploading} onClick={() => fileInputRef.current?.click()}>
          {uploading ? "Uploading..." : "Add photo"}
        </Button>
      </div>
    </div>
  );
}
