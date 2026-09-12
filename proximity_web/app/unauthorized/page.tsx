export default function UnauthorizedPage() {
  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <div className="text-center">
        <h1 className="text-xl font-semibold">Not authorized</h1>
        <p className="mt-2 text-muted-foreground">Your account doesn&apos;t have access to this page.</p>
      </div>
    </div>
  );
}
